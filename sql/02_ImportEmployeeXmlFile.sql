/* =============================================================================
   02_ImportEmployeeXmlFile.sql
   Author  : Senthil P N.  |  senpnathan@gmail.com
   Upwork  : https://www.upwork.com/freelancers/~01c150aa3ba104e1df
   -----------------------------------------------------------------------------
   Imports ONE employee XML file into EmployeeDB.

     EXEC dbo.ImportEmployeeXmlFile @FilePath = N'C:\BulkXmlImport\xml\Employee_1001.xml';

   What it does
     1. Reads the file with OPENROWSET(BULK ..., SINGLE_BLOB) and casts to XML
        (the encoding declared in the file, e.g. UTF-8, is honoured).
     2. Reads EmployeeNo; skips files that have none.
     3. Gets-or-creates the master rows (Department, Job Title, Location,
        Employment Type, Leave Types, Projects) so foreign keys always resolve.
     4. Inserts Employees + 14 child sections inside ONE transaction:
        any error rolls back the whole employee - no half-imported records.
     5. Writes one row to dbo.ImportLog (Success / Skipped / Failed).

   Parameters
     @FilePath         full path readable by the SQL Server service account
     @ReplaceExisting  1 (default) = delete the employee's old data and re-import
                       0 = skip if EmployeeNo already exists
     @RunID            optional GUID that groups files of one batch run

   Return code : 0 = Success, 1 = Skipped, 2 = Failed
   Notes       : Empty / invalid dates and numbers become NULL (TRY_CONVERT),
                 empty <Tag/> elements never turn into 1900-01-01 or 0.
   Requires    : 01_Create_Employee_Tables.sql, permission ADMINISTER BULK OPERATIONS
   Generated from a single column/tag specification (see tools/).
   ============================================================================= */
USE EmployeeDB;
GO

CREATE OR ALTER PROCEDURE dbo.ImportEmployeeXmlFile
    @FilePath        NVARCHAR(1000),
    @ReplaceExisting BIT              = 1,
    @RunID           UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @RunID = ISNULL(@RunID, NEWID());

    DECLARE @XmlData XML,
            @sql     NVARCHAR(MAX),
            @EmployeeNo INT,
            @Rows    INT = 0,
            @Status  NVARCHAR(20),
            @Message NVARCHAR(4000),
            @ErrNo   INT,
            @DeptName NVARCHAR(100),  @JobTitle NVARCHAR(150), @Grade NVARCHAR(20),
            @LocName  NVARCHAR(100),  @TypeName NVARCHAR(30),
            @DepartmentID INT, @JobTitleID INT, @LocationID INT, @EmploymentTypeID INT;

    DECLARE @TsMap TABLE (TimesheetID INT, TsXml XML);   -- header -> entries bridge

    BEGIN TRY
        /* ---- 1. Load the file (BULK needs a literal path, hence dynamic SQL) ---- */
        SET @sql = N'SELECT @XmlOut = CAST(x.BulkColumn AS XML)
                     FROM OPENROWSET(BULK N''' + REPLACE(@FilePath, '''', '''''') + N''', SINGLE_BLOB) AS x;';

        EXEC sp_executesql @sql, N'@XmlOut XML OUTPUT', @XmlOut = @XmlData OUTPUT;

        IF @XmlData IS NULL
            THROW 50001, N'File is empty or is not valid XML.', 1;

        /* ---- 2. Key ---- */
        SET @EmployeeNo = TRY_CONVERT(INT, NULLIF(@XmlData.value('(/Employee/Demographics/EmployeeNo)[1]', 'NVARCHAR(20)'), ''));

        IF @EmployeeNo IS NULL
        BEGIN
            SET @Status  = N'Skipped';
            SET @Message = N'No /Employee/Demographics/EmployeeNo found.';
        END
        ELSE IF @ReplaceExisting = 0 AND EXISTS (SELECT 1 FROM dbo.Employees WHERE EmployeeNo = @EmployeeNo)
        BEGIN
            SET @Status  = N'Skipped';
            SET @Message = N'EmployeeNo already exists and @ReplaceExisting = 0.';
        END
        ELSE
        BEGIN
            BEGIN TRANSACTION;

            /* ---- 3. Remove previous copy (children go with it: ON DELETE CASCADE) ---- */
            DELETE FROM dbo.Employees WHERE EmployeeNo = @EmployeeNo;

            /* ---- 4. Master data: get-or-create ---- */
            SELECT @DeptName = NULLIF(LTRIM(RTRIM(@XmlData.value('(/Employee/Demographics/Department)[1]',     'NVARCHAR(100)'))), ''),
                   @JobTitle = NULLIF(LTRIM(RTRIM(@XmlData.value('(/Employee/Demographics/JobTitle)[1]',       'NVARCHAR(150)'))), ''),
                   @Grade    = NULLIF(LTRIM(RTRIM(@XmlData.value('(/Employee/Demographics/Grade)[1]',          'NVARCHAR(20)'))),  ''),
                   @LocName  = NULLIF(LTRIM(RTRIM(@XmlData.value('(/Employee/Demographics/WorkLocation)[1]',   'NVARCHAR(100)'))), ''),
                   @TypeName = NULLIF(LTRIM(RTRIM(@XmlData.value('(/Employee/Demographics/EmploymentType)[1]', 'NVARCHAR(30)'))),  '');

            IF @DeptName IS NOT NULL
            BEGIN
                SELECT @DepartmentID = DepartmentID FROM dbo.Departments WHERE DepartmentName = @DeptName;
                IF @DepartmentID IS NULL
                BEGIN
                    INSERT INTO dbo.Departments (DepartmentName) VALUES (@DeptName);
                    SET @DepartmentID = SCOPE_IDENTITY();
                END
            END

            IF @JobTitle IS NOT NULL
            BEGIN
                SELECT @JobTitleID = JobTitleID FROM dbo.JobTitles WHERE JobTitle = @JobTitle;
                IF @JobTitleID IS NULL
                BEGIN
                    INSERT INTO dbo.JobTitles (JobTitle, Grade, DepartmentID) VALUES (@JobTitle, @Grade, @DepartmentID);
                    SET @JobTitleID = SCOPE_IDENTITY();
                END
            END

            IF @LocName IS NOT NULL
            BEGIN
                SELECT @LocationID = LocationID FROM dbo.Locations WHERE LocationName = @LocName;
                IF @LocationID IS NULL
                BEGIN
                    INSERT INTO dbo.Locations (LocationName, IsRemote) VALUES (@LocName, CASE WHEN @LocName LIKE N'Remote%' THEN 1 ELSE 0 END);
                    SET @LocationID = SCOPE_IDENTITY();
                END
            END

            IF @TypeName IS NOT NULL
            BEGIN
                SELECT @EmploymentTypeID = EmploymentTypeID FROM dbo.EmploymentTypes WHERE TypeName = @TypeName;
                IF @EmploymentTypeID IS NULL
                BEGIN
                    INSERT INTO dbo.EmploymentTypes (TypeName) VALUES (@TypeName);
                    SET @EmploymentTypeID = SCOPE_IDENTITY();
                END
            END

            /* Leave types and projects can be many per file - set-based get-or-create */
            INSERT INTO dbo.LeaveTypes (LeaveTypeName)
            SELECT DISTINCT x.n
            FROM (SELECT NULLIF(LTRIM(RTRIM(r.value('(LeaveType)[1]', 'NVARCHAR(50)'))), '') AS n
                  FROM @XmlData.nodes('/Employee/Leave') AS T(r)) x
            WHERE x.n IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM dbo.LeaveTypes t WHERE t.LeaveTypeName = x.n);

            INSERT INTO dbo.Projects (ProjectCode, ProjectName)
            SELECT x.Code, MAX(x.Name)
            FROM (SELECT NULLIF(LTRIM(RTRIM(r.value('(ProjectCode)[1]', 'NVARCHAR(50)'))),  '') AS Code,
                         NULLIF(LTRIM(RTRIM(r.value('(ProjectName)[1]', 'NVARCHAR(200)'))), '') AS Name
                  FROM @XmlData.nodes('/Employee/Timesheet/Entry') AS T(r)) x
            WHERE x.Code IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM dbo.Projects p WHERE p.ProjectCode = x.Code)
            GROUP BY x.Code;

            /* ---- 5. Employees (one <Demographics> per file) ---- */
            INSERT INTO dbo.Employees (
                EmployeeNo, Active, EmploymentTypeID, DepartmentID, JobTitleID, LocationID, SourceFile,
                EmployeeCode, Title, FirstName, MiddleName, LastName, DateOfBirth, Gender, MaritalStatus, Nationality, NationalID, PassportNo, TaxID, BloodGroup, Email, PersonalEmail, WorkPhone, Mobile, HireDate, ProbationEndDate, TerminationDate, ManagerEmployeeNo, Status
            )
            SELECT @EmployeeNo,
                   ISNULL(TRY_CONVERT(BIT, NULLIF(r.value('(Active)[1]', 'NVARCHAR(10)'), '')), 1),
                   @EmploymentTypeID, @DepartmentID, @JobTitleID, @LocationID, @FilePath,
                   r.value('(EmployeeCode)[1]', 'NVARCHAR(20)'),
                   r.value('(Title)[1]', 'NVARCHAR(20)'),
                   r.value('(FirstName)[1]', 'NVARCHAR(100)'),
                   r.value('(MiddleName)[1]', 'NVARCHAR(100)'),
                   r.value('(LastName)[1]', 'NVARCHAR(100)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(DateOfBirth)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Gender)[1]', 'NVARCHAR(20)'),
                   r.value('(MaritalStatus)[1]', 'NVARCHAR(30)'),
                   r.value('(Nationality)[1]', 'NVARCHAR(60)'),
                   r.value('(NationalID)[1]', 'NVARCHAR(50)'),
                   r.value('(PassportNo)[1]', 'NVARCHAR(50)'),
                   r.value('(TaxID)[1]', 'NVARCHAR(50)'),
                   r.value('(BloodGroup)[1]', 'NVARCHAR(5)'),
                   r.value('(Email)[1]', 'NVARCHAR(200)'),
                   r.value('(PersonalEmail)[1]', 'NVARCHAR(200)'),
                   r.value('(WorkPhone)[1]', 'NVARCHAR(50)'),
                   r.value('(Mobile)[1]', 'NVARCHAR(50)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(HireDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DATE, NULLIF(r.value('(ProbationEndDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DATE, NULLIF(r.value('(TerminationDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(INT, NULLIF(r.value('(ManagerEmployeeNo)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Status)[1]', 'NVARCHAR(30)')
            FROM @XmlData.nodes('/Employee/Demographics') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* ---- 6. Simple repeating sections ---- */
            /* Addresses */
            INSERT INTO dbo.EmployeeAddresses (EmployeeNo, AddressType, Line1, Line2, City, State, PostalCode, Country, IsPrimary)
            SELECT @EmployeeNo,
                   r.value('(AddressType)[1]', 'NVARCHAR(30)'),
                   r.value('(Line1)[1]', 'NVARCHAR(200)'),
                   r.value('(Line2)[1]', 'NVARCHAR(200)'),
                   r.value('(City)[1]', 'NVARCHAR(100)'),
                   r.value('(State)[1]', 'NVARCHAR(100)'),
                   r.value('(PostalCode)[1]', 'NVARCHAR(20)'),
                   r.value('(Country)[1]', 'NVARCHAR(100)'),
                   ISNULL(TRY_CONVERT(BIT, NULLIF(r.value('(IsPrimary)[1]', 'NVARCHAR(10)'), '')), 0)
            FROM @XmlData.nodes('/Employee/Address') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Emergency contacts */
            INSERT INTO dbo.EmployeeEmergencyContacts (EmployeeNo, Name, Relationship, Phone1, Phone2, Email, Address)
            SELECT @EmployeeNo,
                   r.value('(Name)[1]', 'NVARCHAR(200)'),
                   r.value('(Relationship)[1]', 'NVARCHAR(100)'),
                   r.value('(Phone1)[1]', 'NVARCHAR(50)'),
                   r.value('(Phone2)[1]', 'NVARCHAR(50)'),
                   r.value('(Email)[1]', 'NVARCHAR(200)'),
                   r.value('(Address)[1]', 'NVARCHAR(400)')
            FROM @XmlData.nodes('/Employee/EmergencyContact') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Dependents */
            INSERT INTO dbo.EmployeeDependents (EmployeeNo, Name, Relationship, DateOfBirth, Gender, InsuranceCovered)
            SELECT @EmployeeNo,
                   r.value('(Name)[1]', 'NVARCHAR(200)'),
                   r.value('(Relationship)[1]', 'NVARCHAR(100)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(DateOfBirth)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Gender)[1]', 'NVARCHAR(20)'),
                   ISNULL(TRY_CONVERT(BIT, NULLIF(r.value('(InsuranceCovered)[1]', 'NVARCHAR(10)'), '')), 0)
            FROM @XmlData.nodes('/Employee/Dependent') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Qualifications */
            INSERT INTO dbo.EmployeeQualifications (EmployeeNo, Degree, FieldOfStudy, Institution, YearCompleted, GradeOrScore)
            SELECT @EmployeeNo,
                   r.value('(Degree)[1]', 'NVARCHAR(200)'),
                   r.value('(FieldOfStudy)[1]', 'NVARCHAR(200)'),
                   r.value('(Institution)[1]', 'NVARCHAR(300)'),
                   TRY_CONVERT(INT, NULLIF(r.value('(YearCompleted)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(GradeOrScore)[1]', 'NVARCHAR(50)')
            FROM @XmlData.nodes('/Employee/Qualification') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Work history */
            INSERT INTO dbo.EmployeeWorkHistory (EmployeeNo, Company, JobTitle, StartDate, EndDate, Responsibilities, ReasonForLeaving)
            SELECT @EmployeeNo,
                   r.value('(Company)[1]', 'NVARCHAR(300)'),
                   r.value('(JobTitle)[1]', 'NVARCHAR(200)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(StartDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DATE, NULLIF(r.value('(EndDate)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Responsibilities)[1]', 'NVARCHAR(MAX)'),
                   r.value('(ReasonForLeaving)[1]', 'NVARCHAR(300)')
            FROM @XmlData.nodes('/Employee/WorkHistory') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Skills */
            INSERT INTO dbo.EmployeeSkills (EmployeeNo, SkillName, Category, ProficiencyLevel, YearsExperience)
            SELECT @EmployeeNo,
                   r.value('(SkillName)[1]', 'NVARCHAR(200)'),
                   r.value('(Category)[1]', 'NVARCHAR(100)'),
                   r.value('(ProficiencyLevel)[1]', 'NVARCHAR(30)'),
                   TRY_CONVERT(DECIMAL(4,1), NULLIF(r.value('(YearsExperience)[1]', 'NVARCHAR(30)'), ''))
            FROM @XmlData.nodes('/Employee/Skill') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Certifications */
            INSERT INTO dbo.EmployeeCertifications (EmployeeNo, CertificationName, IssuingBody, IssueDate, ExpiryDate, CredentialID)
            SELECT @EmployeeNo,
                   r.value('(CertificationName)[1]', 'NVARCHAR(300)'),
                   r.value('(IssuingBody)[1]', 'NVARCHAR(200)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(IssueDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DATE, NULLIF(r.value('(ExpiryDate)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(CredentialID)[1]', 'NVARCHAR(100)')
            FROM @XmlData.nodes('/Employee/Certification') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Salary history */
            INSERT INTO dbo.EmployeeSalaryHistory (EmployeeNo, EffectiveDate, BaseSalary, Currency, PayFrequency, Bonus, Reason)
            SELECT @EmployeeNo,
                   TRY_CONVERT(DATE, NULLIF(r.value('(EffectiveDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DECIMAL(18,2), NULLIF(r.value('(BaseSalary)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Currency)[1]', 'NVARCHAR(3)'),
                   r.value('(PayFrequency)[1]', 'NVARCHAR(20)'),
                   TRY_CONVERT(DECIMAL(18,2), NULLIF(r.value('(Bonus)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Reason)[1]', 'NVARCHAR(300)')
            FROM @XmlData.nodes('/Employee/SalaryHistory') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Leave (LeaveType resolved to LeaveTypeID) */
            INSERT INTO dbo.EmployeeLeave (EmployeeNo, LeaveTypeID, StartDate, EndDate, [Days], Status, ApprovedBy, Reason)
            SELECT @EmployeeNo, lt.LeaveTypeID, src.StartDate, src.EndDate, src.[Days], src.Status, src.ApprovedBy, src.Reason
            FROM (SELECT NULLIF(LTRIM(RTRIM(r.value('(LeaveType)[1]', 'NVARCHAR(50)'))), '') AS LeaveTypeName,
                         TRY_CONVERT(DATE, NULLIF(r.value('(StartDate)[1]', 'NVARCHAR(30)'), '')) AS StartDate,
                         TRY_CONVERT(DATE, NULLIF(r.value('(EndDate)[1]', 'NVARCHAR(30)'), '')) AS EndDate,
                         TRY_CONVERT(DECIMAL(5,1), NULLIF(r.value('(Days)[1]', 'NVARCHAR(30)'), '')) AS [Days],
                         r.value('(Status)[1]', 'NVARCHAR(30)') AS Status,
                         r.value('(ApprovedBy)[1]', 'NVARCHAR(200)') AS ApprovedBy,
                         r.value('(Reason)[1]', 'NVARCHAR(500)') AS Reason
                  FROM @XmlData.nodes('/Employee/Leave') AS T(r)) AS src
            LEFT JOIN dbo.LeaveTypes lt ON lt.LeaveTypeName = src.LeaveTypeName;
            SET @Rows += @@ROWCOUNT;

            /* Performance reviews */
            INSERT INTO dbo.EmployeePerformanceReviews (EmployeeNo, ReviewPeriod, ReviewDate, Reviewer, Rating, Goals, Comments)
            SELECT @EmployeeNo,
                   r.value('(ReviewPeriod)[1]', 'NVARCHAR(50)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(ReviewDate)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Reviewer)[1]', 'NVARCHAR(200)'),
                   TRY_CONVERT(DECIMAL(3,1), NULLIF(r.value('(Rating)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Goals)[1]', 'NVARCHAR(MAX)'),
                   r.value('(Comments)[1]', 'NVARCHAR(MAX)')
            FROM @XmlData.nodes('/Employee/PerformanceReview') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Training */
            INSERT INTO dbo.EmployeeTraining (EmployeeNo, CourseName, Provider, CompletedDate, DurationHours, Cost, Result)
            SELECT @EmployeeNo,
                   r.value('(CourseName)[1]', 'NVARCHAR(300)'),
                   r.value('(Provider)[1]', 'NVARCHAR(200)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(CompletedDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DECIMAL(6,1), NULLIF(r.value('(DurationHours)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DECIMAL(18,2), NULLIF(r.value('(Cost)[1]', 'NVARCHAR(30)'), '')),
                   r.value('(Result)[1]', 'NVARCHAR(50)')
            FROM @XmlData.nodes('/Employee/Training') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* Assets */
            INSERT INTO dbo.EmployeeAssets (EmployeeNo, AssetTag, AssetType, Description, IssuedDate, ReturnedDate)
            SELECT @EmployeeNo,
                   r.value('(AssetTag)[1]', 'NVARCHAR(50)'),
                   r.value('(AssetType)[1]', 'NVARCHAR(100)'),
                   r.value('(Description)[1]', 'NVARCHAR(300)'),
                   TRY_CONVERT(DATE, NULLIF(r.value('(IssuedDate)[1]', 'NVARCHAR(30)'), '')),
                   TRY_CONVERT(DATE, NULLIF(r.value('(ReturnedDate)[1]', 'NVARCHAR(30)'), ''))
            FROM @XmlData.nodes('/Employee/Asset') AS T(r);
            SET @Rows += @@ROWCOUNT;

            /* ---- 7. Timesheets (header) + TimesheetEntries (lines) ----
               MERGE ... ON 1 = 0 lets OUTPUT return the new identity together with
               the source XML fragment, so every entry is tied to the exact header it
               belongs to - no reliance on row order. */
            MERGE dbo.EmployeeTimesheets AS tgt
            USING (SELECT TRY_CONVERT(DATE, NULLIF(t.value('(WeekStartDate)[1]', 'NVARCHAR(30)'), '')) AS WeekStartDate,
                          t.value('(Status)[1]', 'NVARCHAR(30)') AS Status,
                          t.value('(ApprovedBy)[1]', 'NVARCHAR(200)') AS ApprovedBy,
                          t.query('.') AS TsXml
                   FROM @XmlData.nodes('/Employee/Timesheet') AS X(t)) AS src
               ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (EmployeeNo, WeekStartDate, Status, ApprovedBy)
                VALUES (@EmployeeNo, src.WeekStartDate, src.Status, src.ApprovedBy)
            OUTPUT inserted.TimesheetID, src.TsXml INTO @TsMap (TimesheetID, TsXml);
            SET @Rows += @@ROWCOUNT;

            INSERT INTO dbo.TimesheetEntries (TimesheetID, ProjectID, WorkDate, Task, Hours, Notes)
            SELECT src.TimesheetID, p.ProjectID, src.WorkDate, src.Task, src.Hours, src.Notes
            FROM (SELECT m.TimesheetID,
                         NULLIF(LTRIM(RTRIM(e.value('(ProjectCode)[1]', 'NVARCHAR(50)'))), '') AS ProjectCode,
                         TRY_CONVERT(DATE, NULLIF(e.value('(WorkDate)[1]', 'NVARCHAR(30)'), '')) AS WorkDate,
                         e.value('(Task)[1]', 'NVARCHAR(300)') AS Task,
                         TRY_CONVERT(DECIMAL(4,2), NULLIF(e.value('(Hours)[1]', 'NVARCHAR(30)'), '')) AS Hours,
                         e.value('(Notes)[1]', 'NVARCHAR(500)') AS Notes
                  FROM @TsMap m
                  CROSS APPLY m.TsXml.nodes('/Timesheet/Entry') AS E(e)) AS src
            LEFT JOIN dbo.Projects p ON p.ProjectCode = src.ProjectCode;
            SET @Rows += @@ROWCOUNT;

            COMMIT TRANSACTION;

            SET @Status  = N'Success';
            SET @Message = CONCAT(N'Imported EmployeeNo ', @EmployeeNo, N': ', @Rows, N' rows written.');
        END

        INSERT INTO dbo.ImportLog (RunID, FilePath, EmployeeNo, Status, RowsInserted, Message)
        VALUES (@RunID, @FilePath, @EmployeeNo, @Status, NULLIF(@Rows, 0), @Message);

        RETURN CASE @Status WHEN N'Success' THEN 0 WHEN N'Skipped' THEN 1 ELSE 2 END;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SET @ErrNo   = ERROR_NUMBER();
        SET @Message = LEFT(CONCAT(ERROR_MESSAGE(), N' (line ', ERROR_LINE(), N')'), 4000);

        INSERT INTO dbo.ImportLog (RunID, FilePath, EmployeeNo, Status, Message, ErrorNumber)
        VALUES (@RunID, @FilePath, @EmployeeNo, N'Failed', @Message, @ErrNo);

        RETURN 2;
    END CATCH
END
GO
