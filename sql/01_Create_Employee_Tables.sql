/* =============================================================================
   01_Create_Employee_Tables.sql
   Author  : Senthil P N.  |  senpnathan@gmail.com
   Upwork  : https://www.upwork.com/freelancers/~01c150aa3ba104e1df
   -----------------------------------------------------------------------------
   Project : Bulk XML Import (SQL Server / T-SQL)
   Purpose : Creates the EmployeeDB database with
               - 6 master / lookup tables (Departments, JobTitles, Locations,
                 EmploymentTypes, LeaveTypes, Projects)
               - the Employees table (foreign keys into the masters)
               - 14 employee child tables
               - an import audit log and a reporting view
   Target  : SQL Server 2016 SP1+ (CREATE OR ALTER, TRY_CONVERT, THROW)
   Re-run  : Safe. Every object is created only if it does not exist yet.
             A teardown script is included (commented out) at the bottom.

   Design notes
   * Master tables hold each Department / Job Title / Location ... exactly once.
     The import procedure "gets or creates" them by name, so new values found
     in an XML file are added automatically instead of failing.
   * dbo.Employees is the parent table; EmployeeNo (from the XML) is its key.
   * Every child table references Employees with ON DELETE CASCADE, so a
     re-import only needs:  DELETE FROM dbo.Employees WHERE EmployeeNo = @n
   * EmployeeTimesheets -> TimesheetEntries is a two-level parent/child pair
     (same pattern as Requests -> RequestTests in the patient sample).
   * dbo.ImportLog records one row per file per run (Success/Skipped/Failed).
   ============================================================================= */

SET NOCOUNT ON;
GO

IF DB_ID(N'EmployeeDB') IS NULL
    CREATE DATABASE EmployeeDB;
GO

USE EmployeeDB;
GO

/* ===========================================================================
   PART A - MASTER / LOOKUP TABLES
   =========================================================================== */

/* ---- A1. Departments (self-referencing hierarchy) ------------------------ */
IF OBJECT_ID(N'dbo.Departments', N'U') IS NULL
CREATE TABLE dbo.Departments (
    DepartmentID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Departments PRIMARY KEY,
    DepartmentCode     NVARCHAR(20)  NULL,
    DepartmentName     NVARCHAR(100) NOT NULL,
    ParentDepartmentID INT           NULL CONSTRAINT FK_Departments_Parent REFERENCES dbo.Departments (DepartmentID),
    CostCenter         NVARCHAR(30)  NULL,
    HeadEmployeeNo     INT           NULL,          -- soft reference to Employees (avoids circular FK)
    IsActive           BIT           NOT NULL CONSTRAINT DF_Departments_IsActive DEFAULT (1),
    CreatedAt          DATETIME2(0)  NOT NULL CONSTRAINT DF_Departments_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_Departments_Name UNIQUE (DepartmentName)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Departments_Code' AND object_id = OBJECT_ID(N'dbo.Departments'))
    CREATE UNIQUE INDEX UX_Departments_Code ON dbo.Departments (DepartmentCode) WHERE DepartmentCode IS NOT NULL;
GO

/* ---- A2. Job titles ------------------------------------------------------- */
IF OBJECT_ID(N'dbo.JobTitles', N'U') IS NULL
CREATE TABLE dbo.JobTitles (
    JobTitleID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_JobTitles PRIMARY KEY,
    JobTitle     NVARCHAR(150) NOT NULL,
    Grade        NVARCHAR(20)  NULL,
    DepartmentID INT           NULL CONSTRAINT FK_JobTitles_Departments REFERENCES dbo.Departments (DepartmentID),
    IsActive     BIT           NOT NULL CONSTRAINT DF_JobTitles_IsActive DEFAULT (1),
    CONSTRAINT UQ_JobTitles_Title UNIQUE (JobTitle)
);
GO

/* ---- A3. Work locations --------------------------------------------------- */
IF OBJECT_ID(N'dbo.Locations', N'U') IS NULL
CREATE TABLE dbo.Locations (
    LocationID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Locations PRIMARY KEY,
    LocationName NVARCHAR(100) NOT NULL,
    City         NVARCHAR(100) NULL,
    Country      NVARCHAR(100) NULL,
    IsRemote     BIT           NOT NULL CONSTRAINT DF_Locations_IsRemote DEFAULT (0),
    CONSTRAINT UQ_Locations_Name UNIQUE (LocationName)
);
GO

/* ---- A4. Employment types (seeded) ---------------------------------------- */
IF OBJECT_ID(N'dbo.EmploymentTypes', N'U') IS NULL
CREATE TABLE dbo.EmploymentTypes (
    EmploymentTypeID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmploymentTypes PRIMARY KEY,
    TypeName         NVARCHAR(30) NOT NULL,
    CONSTRAINT UQ_EmploymentTypes_Name UNIQUE (TypeName)
);
GO

/* ---- A5. Leave types (seeded) --------------------------------------------- */
IF OBJECT_ID(N'dbo.LeaveTypes', N'U') IS NULL
CREATE TABLE dbo.LeaveTypes (
    LeaveTypeID        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LeaveTypes PRIMARY KEY,
    LeaveTypeName      NVARCHAR(50) NOT NULL,
    DefaultDaysPerYear DECIMAL(5,1) NULL,
    IsPaid             BIT          NOT NULL CONSTRAINT DF_LeaveTypes_IsPaid DEFAULT (1),
    CONSTRAINT UQ_LeaveTypes_Name UNIQUE (LeaveTypeName)
);
GO

/* ---- A6. Projects (referenced by timesheet entries) ------------------------ */
IF OBJECT_ID(N'dbo.Projects', N'U') IS NULL
CREATE TABLE dbo.Projects (
    ProjectID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Projects PRIMARY KEY,
    ProjectCode NVARCHAR(50)  NOT NULL,
    ProjectName NVARCHAR(200) NULL,
    IsBillable  BIT           NOT NULL CONSTRAINT DF_Projects_IsBillable DEFAULT (1),
    IsActive    BIT           NOT NULL CONSTRAINT DF_Projects_IsActive DEFAULT (1),
    CONSTRAINT UQ_Projects_Code UNIQUE (ProjectCode)
);
GO

/* ---- Seed data (idempotent) ------------------------------------------------ */
INSERT INTO dbo.EmploymentTypes (TypeName)
SELECT v.TypeName FROM (VALUES (N'Full-time'), (N'Part-time'), (N'Contract'), (N'Intern'), (N'Casual')) v(TypeName)
WHERE NOT EXISTS (SELECT 1 FROM dbo.EmploymentTypes t WHERE t.TypeName = v.TypeName);

INSERT INTO dbo.LeaveTypes (LeaveTypeName, DefaultDaysPerYear, IsPaid)
SELECT v.n, v.d, v.p FROM (VALUES
    (N'Annual', 20.0, 1), (N'Sick', 10.0, 1), (N'Parental', 90.0, 1),
    (N'Study', 5.0, 1), (N'Bereavement', 3.0, 1), (N'Unpaid', NULL, 0)) v(n, d, p)
WHERE NOT EXISTS (SELECT 1 FROM dbo.LeaveTypes t WHERE t.LeaveTypeName = v.n);

INSERT INTO dbo.Departments (DepartmentCode, DepartmentName, CostCenter)
SELECT v.c, v.n, v.cc FROM (VALUES
    (N'ENG', N'Engineering',       N'CC-100'), (N'HR',  N'Human Resources',   N'CC-200'),
    (N'FIN', N'Finance',           N'CC-300'), (N'SAL', N'Sales',             N'CC-400'),
    (N'MKT', N'Marketing',         N'CC-500'), (N'OPS', N'Operations',        N'CC-600'),
    (N'SUP', N'Customer Support',  N'CC-700'), (N'IT',  N'IT Services',       N'CC-800')) v(c, n, cc)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Departments d WHERE d.DepartmentName = v.n);
GO

/* ===========================================================================
   PART B - EMPLOYEES (parent table)
   =========================================================================== */
IF OBJECT_ID(N'dbo.Employees', N'U') IS NULL
CREATE TABLE dbo.Employees (
    EmployeeNo         INT           NOT NULL CONSTRAINT PK_Employees PRIMARY KEY,
    EmployeeCode       NVARCHAR(20)  NULL,
    Active             BIT           NOT NULL CONSTRAINT DF_Employees_Active DEFAULT (1),
    Title              NVARCHAR(20)  NULL,
    FirstName          NVARCHAR(100) NOT NULL,
    MiddleName         NVARCHAR(100) NULL,
    LastName           NVARCHAR(100) NOT NULL,
    DateOfBirth        DATE          NULL,
    Gender             NVARCHAR(20)  NULL,
    MaritalStatus      NVARCHAR(30)  NULL,
    Nationality        NVARCHAR(60)  NULL,
    NationalID         NVARCHAR(50)  NULL,
    PassportNo         NVARCHAR(50)  NULL,
    TaxID              NVARCHAR(50)  NULL,
    BloodGroup         NVARCHAR(5)   NULL,
    Email              NVARCHAR(200) NULL,
    PersonalEmail      NVARCHAR(200) NULL,
    WorkPhone          NVARCHAR(50)  NULL,
    Mobile             NVARCHAR(50)  NULL,
    HireDate           DATE          NULL,
    ProbationEndDate   DATE          NULL,
    TerminationDate    DATE          NULL,
    EmploymentTypeID   INT           NULL CONSTRAINT FK_Employees_EmploymentTypes REFERENCES dbo.EmploymentTypes (EmploymentTypeID),
    DepartmentID       INT           NULL CONSTRAINT FK_Employees_Departments     REFERENCES dbo.Departments (DepartmentID),
    JobTitleID         INT           NULL CONSTRAINT FK_Employees_JobTitles       REFERENCES dbo.JobTitles (JobTitleID),
    LocationID         INT           NULL CONSTRAINT FK_Employees_Locations       REFERENCES dbo.Locations (LocationID),
    ManagerEmployeeNo  INT           NULL,      -- soft reference: manager file may be imported later
    Status             NVARCHAR(30)  NULL,      -- Active / On Leave / Terminated
    SourceFile         NVARCHAR(1000) NULL,     -- which XML file this row came from
    ImportedAt         DATETIME2(0)  NOT NULL CONSTRAINT DF_Employees_ImportedAt DEFAULT (SYSUTCDATETIME()),
    INDEX IX_Employees_Department (DepartmentID),
    INDEX IX_Employees_JobTitle   (JobTitleID),
    INDEX IX_Employees_Location   (LocationID),
    INDEX IX_Employees_LastName   (LastName, FirstName),
    INDEX IX_Employees_Manager    (ManagerEmployeeNo)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Employees_EmployeeCode' AND object_id = OBJECT_ID(N'dbo.Employees'))
    CREATE UNIQUE INDEX UX_Employees_EmployeeCode ON dbo.Employees (EmployeeCode) WHERE EmployeeCode IS NOT NULL;
GO

/* ===========================================================================
   PART C - EMPLOYEE CHILD TABLES (many rows per employee)
   =========================================================================== */
IF OBJECT_ID(N'dbo.EmployeeAddresses', N'U') IS NULL
CREATE TABLE dbo.EmployeeAddresses (
    AddressID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeAddresses PRIMARY KEY,
    EmployeeNo  INT NOT NULL CONSTRAINT FK_EmployeeAddresses_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    AddressType NVARCHAR(30)  NULL,          -- Home / Postal / Work
    Line1       NVARCHAR(200) NULL,
    Line2       NVARCHAR(200) NULL,
    City        NVARCHAR(100) NULL,
    State       NVARCHAR(100) NULL,
    PostalCode  NVARCHAR(20)  NULL,
    Country     NVARCHAR(100) NULL,
    IsPrimary   BIT NOT NULL CONSTRAINT DF_EmployeeAddresses_IsPrimary DEFAULT (0),
    INDEX IX_EmployeeAddresses_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeEmergencyContacts', N'U') IS NULL
CREATE TABLE dbo.EmployeeEmergencyContacts (
    ContactID    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeEmergencyContacts PRIMARY KEY,
    EmployeeNo   INT NOT NULL CONSTRAINT FK_EmployeeEmergencyContacts_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    Name         NVARCHAR(200) NULL,
    Relationship NVARCHAR(100) NULL,
    Phone1       NVARCHAR(50)  NULL,
    Phone2       NVARCHAR(50)  NULL,
    Email        NVARCHAR(200) NULL,
    Address      NVARCHAR(400) NULL,
    INDEX IX_EmployeeEmergencyContacts_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeDependents', N'U') IS NULL
CREATE TABLE dbo.EmployeeDependents (
    DependentID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeDependents PRIMARY KEY,
    EmployeeNo       INT NOT NULL CONSTRAINT FK_EmployeeDependents_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    Name             NVARCHAR(200) NULL,
    Relationship     NVARCHAR(100) NULL,
    DateOfBirth      DATE          NULL,
    Gender           NVARCHAR(20)  NULL,
    InsuranceCovered BIT NOT NULL CONSTRAINT DF_EmployeeDependents_Ins DEFAULT (0),
    INDEX IX_EmployeeDependents_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeQualifications', N'U') IS NULL
CREATE TABLE dbo.EmployeeQualifications (
    QualificationID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeQualifications PRIMARY KEY,
    EmployeeNo      INT NOT NULL CONSTRAINT FK_EmployeeQualifications_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    Degree          NVARCHAR(200) NULL,
    FieldOfStudy    NVARCHAR(200) NULL,
    Institution     NVARCHAR(300) NULL,
    YearCompleted   INT           NULL,
    GradeOrScore    NVARCHAR(50)  NULL,
    INDEX IX_EmployeeQualifications_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeWorkHistory', N'U') IS NULL
CREATE TABLE dbo.EmployeeWorkHistory (
    WorkHistoryID    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeWorkHistory PRIMARY KEY,
    EmployeeNo       INT NOT NULL CONSTRAINT FK_EmployeeWorkHistory_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    Company          NVARCHAR(300) NULL,
    JobTitle         NVARCHAR(200) NULL,
    StartDate        DATE          NULL,
    EndDate          DATE          NULL,
    Responsibilities NVARCHAR(MAX) NULL,
    ReasonForLeaving NVARCHAR(300) NULL,
    INDEX IX_EmployeeWorkHistory_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeSkills', N'U') IS NULL
CREATE TABLE dbo.EmployeeSkills (
    SkillID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeSkills PRIMARY KEY,
    EmployeeNo       INT NOT NULL CONSTRAINT FK_EmployeeSkills_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    SkillName        NVARCHAR(200) NULL,
    Category         NVARCHAR(100) NULL,
    ProficiencyLevel NVARCHAR(30)  NULL,      -- Beginner / Intermediate / Advanced / Expert
    YearsExperience  DECIMAL(4,1)  NULL,
    INDEX IX_EmployeeSkills_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeCertifications', N'U') IS NULL
CREATE TABLE dbo.EmployeeCertifications (
    CertificationID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeCertifications PRIMARY KEY,
    EmployeeNo        INT NOT NULL CONSTRAINT FK_EmployeeCertifications_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    CertificationName NVARCHAR(300) NULL,
    IssuingBody       NVARCHAR(200) NULL,
    IssueDate         DATE          NULL,
    ExpiryDate        DATE          NULL,
    CredentialID      NVARCHAR(100) NULL,
    INDEX IX_EmployeeCertifications_EmployeeNo (EmployeeNo),
    INDEX IX_EmployeeCertifications_Expiry (ExpiryDate)
);
GO

IF OBJECT_ID(N'dbo.EmployeeSalaryHistory', N'U') IS NULL
CREATE TABLE dbo.EmployeeSalaryHistory (
    SalaryID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeSalaryHistory PRIMARY KEY,
    EmployeeNo    INT NOT NULL CONSTRAINT FK_EmployeeSalaryHistory_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    EffectiveDate DATE          NULL,
    BaseSalary    DECIMAL(18,2) NULL,
    Currency      NVARCHAR(3)   NULL,
    PayFrequency  NVARCHAR(20)  NULL,         -- Annual / Monthly / Hourly
    Bonus         DECIMAL(18,2) NULL,
    Reason        NVARCHAR(300) NULL,
    INDEX IX_EmployeeSalaryHistory_EmployeeNo (EmployeeNo, EffectiveDate)
);
GO

IF OBJECT_ID(N'dbo.EmployeeLeave', N'U') IS NULL
CREATE TABLE dbo.EmployeeLeave (
    LeaveID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeLeave PRIMARY KEY,
    EmployeeNo  INT NOT NULL CONSTRAINT FK_EmployeeLeave_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    LeaveTypeID INT NULL CONSTRAINT FK_EmployeeLeave_LeaveTypes REFERENCES dbo.LeaveTypes (LeaveTypeID),
    StartDate   DATE          NULL,
    EndDate     DATE          NULL,
    [Days]      DECIMAL(5,1)  NULL,
    Status      NVARCHAR(30)  NULL,           -- Approved / Pending / Rejected
    ApprovedBy  NVARCHAR(200) NULL,
    Reason      NVARCHAR(500) NULL,
    INDEX IX_EmployeeLeave_EmployeeNo (EmployeeNo, StartDate)
);
GO

IF OBJECT_ID(N'dbo.EmployeePerformanceReviews', N'U') IS NULL
CREATE TABLE dbo.EmployeePerformanceReviews (
    ReviewID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeePerformanceReviews PRIMARY KEY,
    EmployeeNo   INT NOT NULL CONSTRAINT FK_EmployeePerformanceReviews_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    ReviewPeriod NVARCHAR(50)  NULL,
    ReviewDate   DATE          NULL,
    Reviewer     NVARCHAR(200) NULL,
    Rating       DECIMAL(3,1)  NULL,          -- 1.0 - 5.0
    Goals        NVARCHAR(MAX) NULL,
    Comments     NVARCHAR(MAX) NULL,
    INDEX IX_EmployeePerformanceReviews_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeTraining', N'U') IS NULL
CREATE TABLE dbo.EmployeeTraining (
    TrainingID    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeTraining PRIMARY KEY,
    EmployeeNo    INT NOT NULL CONSTRAINT FK_EmployeeTraining_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    CourseName    NVARCHAR(300) NULL,
    Provider      NVARCHAR(200) NULL,
    CompletedDate DATE          NULL,
    DurationHours DECIMAL(6,1)  NULL,
    Cost          DECIMAL(18,2) NULL,
    Result        NVARCHAR(50)  NULL,         -- Passed / Failed / Attended
    INDEX IX_EmployeeTraining_EmployeeNo (EmployeeNo)
);
GO

IF OBJECT_ID(N'dbo.EmployeeAssets', N'U') IS NULL
CREATE TABLE dbo.EmployeeAssets (
    AssetID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeAssets PRIMARY KEY,
    EmployeeNo   INT NOT NULL CONSTRAINT FK_EmployeeAssets_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    AssetTag     NVARCHAR(50)  NULL,
    AssetType    NVARCHAR(100) NULL,
    Description  NVARCHAR(300) NULL,
    IssuedDate   DATE          NULL,
    ReturnedDate DATE          NULL,
    INDEX IX_EmployeeAssets_EmployeeNo (EmployeeNo)
);
GO

/* ---- Two-level parent / child: Timesheet header -> daily entries ------------ */
IF OBJECT_ID(N'dbo.EmployeeTimesheets', N'U') IS NULL
CREATE TABLE dbo.EmployeeTimesheets (
    TimesheetID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeTimesheets PRIMARY KEY,
    EmployeeNo    INT NOT NULL CONSTRAINT FK_EmployeeTimesheets_Employees REFERENCES dbo.Employees (EmployeeNo) ON DELETE CASCADE,
    WeekStartDate DATE          NULL,
    Status        NVARCHAR(30)  NULL,         -- Draft / Submitted / Approved
    ApprovedBy    NVARCHAR(200) NULL,
    INDEX IX_EmployeeTimesheets_EmployeeNo (EmployeeNo, WeekStartDate)
);
GO

IF OBJECT_ID(N'dbo.TimesheetEntries', N'U') IS NULL
CREATE TABLE dbo.TimesheetEntries (
    EntryID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TimesheetEntries PRIMARY KEY,
    TimesheetID INT NOT NULL CONSTRAINT FK_TimesheetEntries_Timesheets REFERENCES dbo.EmployeeTimesheets (TimesheetID) ON DELETE CASCADE,
    ProjectID   INT NULL CONSTRAINT FK_TimesheetEntries_Projects REFERENCES dbo.Projects (ProjectID),
    WorkDate    DATE          NULL,
    Task        NVARCHAR(300) NULL,
    Hours       DECIMAL(4,2)  NULL,
    Notes       NVARCHAR(500) NULL,
    INDEX IX_TimesheetEntries_TimesheetID (TimesheetID),
    INDEX IX_TimesheetEntries_ProjectID (ProjectID)
);
GO

/* ===========================================================================
   PART D - IMPORT AUDIT LOG
   =========================================================================== */
IF OBJECT_ID(N'dbo.ImportLog', N'U') IS NULL
CREATE TABLE dbo.ImportLog (
    LogID        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ImportLog PRIMARY KEY,
    RunID        UNIQUEIDENTIFIER NOT NULL,
    FilePath     NVARCHAR(1000)   NULL,
    EmployeeNo   INT              NULL,
    Status       NVARCHAR(20)     NOT NULL,    -- Success / Skipped / Failed
    RowsInserted INT              NULL,
    Message      NVARCHAR(4000)   NULL,
    ErrorNumber  INT              NULL,
    LoggedAt     DATETIME2(0)     NOT NULL CONSTRAINT DF_ImportLog_LoggedAt DEFAULT (SYSUTCDATETIME()),
    INDEX IX_ImportLog_RunID (RunID)
);
GO

/* ===========================================================================
   PART E - REPORTING VIEW
   =========================================================================== */
CREATE OR ALTER VIEW dbo.vw_EmployeeOverview
AS
SELECT  e.EmployeeNo,
        e.EmployeeCode,
        FullName       = CONCAT(e.FirstName, ' ', e.LastName),
        Department     = d.DepartmentName,
        JobTitle       = j.JobTitle,
        j.Grade,
        EmploymentType = et.TypeName,
        WorkLocation   = l.LocationName,
        e.Status,
        e.HireDate,
        YearsOfService = DATEDIFF(YEAR, e.HireDate, ISNULL(e.TerminationDate, CAST(GETDATE() AS DATE))),
        ManagerName    = CONCAT(m.FirstName, ' ', m.LastName),
        CurrentSalary  = s.BaseSalary,
        s.Currency,
        Skills         = (SELECT COUNT(*) FROM dbo.EmployeeSkills         x WHERE x.EmployeeNo = e.EmployeeNo),
        Certifications = (SELECT COUNT(*) FROM dbo.EmployeeCertifications x WHERE x.EmployeeNo = e.EmployeeNo),
        LeaveRecords   = (SELECT COUNT(*) FROM dbo.EmployeeLeave          x WHERE x.EmployeeNo = e.EmployeeNo),
        LatestRating   = (SELECT TOP (1) r.Rating FROM dbo.EmployeePerformanceReviews r
                           WHERE r.EmployeeNo = e.EmployeeNo ORDER BY r.ReviewDate DESC)
FROM    dbo.Employees e
LEFT JOIN dbo.Departments     d  ON d.DepartmentID     = e.DepartmentID
LEFT JOIN dbo.JobTitles       j  ON j.JobTitleID       = e.JobTitleID
LEFT JOIN dbo.EmploymentTypes et ON et.EmploymentTypeID = e.EmploymentTypeID
LEFT JOIN dbo.Locations       l  ON l.LocationID       = e.LocationID
LEFT JOIN dbo.Employees       m  ON m.EmployeeNo       = e.ManagerEmployeeNo
OUTER APPLY (SELECT TOP (1) h.BaseSalary, h.Currency
             FROM dbo.EmployeeSalaryHistory h
             WHERE h.EmployeeNo = e.EmployeeNo
             ORDER BY h.EffectiveDate DESC) s;
GO

PRINT 'EmployeeDB schema is ready: 6 master tables, Employees, 14 child tables, ImportLog, 1 view.';
GO

/* =============================================================================
   TEARDOWN (development only) - uncomment and run to remove everything
   =============================================================================
-- DROP VIEW  IF EXISTS dbo.vw_EmployeeOverview;
-- DROP TABLE IF EXISTS dbo.TimesheetEntries, dbo.EmployeeTimesheets, dbo.EmployeeAssets,
--      dbo.EmployeeTraining, dbo.EmployeePerformanceReviews, dbo.EmployeeLeave,
--      dbo.EmployeeSalaryHistory, dbo.EmployeeCertifications, dbo.EmployeeSkills,
--      dbo.EmployeeWorkHistory, dbo.EmployeeQualifications, dbo.EmployeeDependents,
--      dbo.EmployeeEmergencyContacts, dbo.EmployeeAddresses, dbo.Employees,
--      dbo.Projects, dbo.LeaveTypes, dbo.EmploymentTypes, dbo.Locations,
--      dbo.JobTitles, dbo.Departments, dbo.ImportLog;
   ============================================================================= */
