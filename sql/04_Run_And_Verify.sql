/* =============================================================================
   04_Run_And_Verify.sql
   Author  : Senthil P N.  |  senpnathan@gmail.com
   Upwork  : https://www.upwork.com/freelancers/~01c150aa3ba104e1df
   -----------------------------------------------------------------------------
   Run the batch import, then check the results.
   EDIT the folder path below to where you copied sample-data\xml
   (the folder must be readable by the SQL Server service account).
   ============================================================================= */
USE EmployeeDB;
GO

/* ---- 1. RUN THE IMPORT ---------------------------------------------------- */
EXEC dbo.ImportEmployeeData_From_XmlFiles
     @FolderPath = N'C:\BulkXmlImport\xml';
     -- , @ReplaceExisting = 0     -- skip employees that already exist
     -- , @StopOnError     = 1     -- stop at first failed file
GO

/* Import a single file instead:
EXEC dbo.ImportEmployeeXmlFile @FilePath = N'C:\BulkXmlImport\xml\Employee_1001.xml';
*/

/* ---- 2. ROW COUNTS PER TABLE ---------------------------------------------- */
SELECT t.name AS TableName, SUM(p.rows) AS [RowCount]
FROM   sys.tables t
JOIN   sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE  t.schema_id = SCHEMA_ID('dbo')
GROUP BY t.name
ORDER BY t.name;
GO

/* ---- 3. EMPLOYEE OVERVIEW (view: joins Department, Job Title, Location ...) - */
SELECT * FROM dbo.vw_EmployeeOverview ORDER BY EmployeeNo;
GO

/* ---- 4. IMPORT LOG - latest run ------------------------------------------- */
SELECT TOP (50) LogID, RunID, FilePath, EmployeeNo, Status, RowsInserted, Message, LoggedAt
FROM   dbo.ImportLog
ORDER BY LogID DESC;
GO

/* ---- 5. EXAMPLE REPORTS ---------------------------------------------------- */

-- 5a. Headcount and average salary by department
SELECT  d.DepartmentName,
        Headcount     = COUNT(*),
        AvgSalaryUSD  = AVG(CASE WHEN o.Currency = 'USD' THEN o.CurrentSalary END)
FROM    dbo.Employees e
JOIN    dbo.Departments d ON d.DepartmentID = e.DepartmentID
LEFT JOIN dbo.vw_EmployeeOverview o ON o.EmployeeNo = e.EmployeeNo
WHERE   e.Active = 1
GROUP BY d.DepartmentName
ORDER BY Headcount DESC;

-- 5b. Certifications that expire in the next 12 months
SELECT  e.EmployeeNo, CONCAT(e.FirstName, ' ', e.LastName) AS Employee,
        c.CertificationName, c.ExpiryDate
FROM    dbo.EmployeeCertifications c
JOIN    dbo.Employees e ON e.EmployeeNo = c.EmployeeNo
WHERE   c.ExpiryDate BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(MONTH, 12, CAST(GETDATE() AS DATE))
ORDER BY c.ExpiryDate;

-- 5c. Leave taken per employee and leave type
SELECT  e.EmployeeNo, CONCAT(e.FirstName, ' ', e.LastName) AS Employee,
        lt.LeaveTypeName, SUM(l.[Days]) AS DaysTaken
FROM    dbo.EmployeeLeave l
JOIN    dbo.Employees e   ON e.EmployeeNo = l.EmployeeNo
JOIN    dbo.LeaveTypes lt ON lt.LeaveTypeID = l.LeaveTypeID
WHERE   l.Status = 'Approved'
GROUP BY e.EmployeeNo, e.FirstName, e.LastName, lt.LeaveTypeName
ORDER BY e.EmployeeNo, lt.LeaveTypeName;

-- 5d. Hours booked per project (timesheet header -> entries -> project master)
SELECT  p.ProjectCode, p.ProjectName, TotalHours = SUM(te.Hours), Employees = COUNT(DISTINCT ts.EmployeeNo)
FROM    dbo.TimesheetEntries te
JOIN    dbo.EmployeeTimesheets ts ON ts.TimesheetID = te.TimesheetID
JOIN    dbo.Projects p            ON p.ProjectID    = te.ProjectID
GROUP BY p.ProjectCode, p.ProjectName
ORDER BY TotalHours DESC;

-- 5e. Org chart: who reports to whom
SELECT  Manager = CONCAT(m.FirstName, ' ', m.LastName), Employee = CONCAT(e.FirstName, ' ', e.LastName), o.JobTitle
FROM    dbo.Employees e
LEFT JOIN dbo.Employees m ON m.EmployeeNo = e.ManagerEmployeeNo
JOIN    dbo.vw_EmployeeOverview o ON o.EmployeeNo = e.EmployeeNo
ORDER BY Manager, Employee;
GO
