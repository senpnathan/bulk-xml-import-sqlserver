/* =============================================================================
   03_ImportEmployeeData_From_XmlFiles.sql
   Author  : Senthil P N.  |  senpnathan@gmail.com
   Upwork  : https://www.upwork.com/freelancers/~01c150aa3ba104e1df
   -----------------------------------------------------------------------------
   Batch importer: reads EVERY *.xml file in a folder and calls
   dbo.ImportEmployeeXmlFile for each one.

     EXEC dbo.ImportEmployeeData_From_XmlFiles
          @FolderPath = N'C:\BulkXmlImport\xml';

   Parameters
     @FolderPath       folder that contains the XML files (on the SQL Server host)
     @FilePattern      LIKE pattern for file names, default N'%.xml'
     @ReplaceExisting  1 = re-import employees that already exist (default)
                       0 = skip employees that already exist
     @StopOnError      1 = stop the batch at the first failed file (default 0)

   Output
     * live progress messages (RAISERROR ... WITH NOWAIT)
     * a result set with the outcome of every file in this run
     * a summary row (Success / Skipped / Failed counts)

   Files are listed with master.sys.xp_dirtree, so xp_cmdshell does NOT have to
   be enabled. One bad file never stops the others (unless @StopOnError = 1):
   its error is recorded in dbo.ImportLog and the batch carries on.
   Requires : 02_ImportEmployeeXmlFile.sql
   ============================================================================= */
USE EmployeeDB;
GO

CREATE OR ALTER PROCEDURE dbo.ImportEmployeeData_From_XmlFiles
    @FolderPath      NVARCHAR(500),
    @FilePattern     NVARCHAR(100) = N'%.xml',
    @ReplaceExisting BIT           = 1,
    @StopOnError     BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RunID    UNIQUEIDENTIFIER = NEWID(),
            @Folder   NVARCHAR(500),
            @FileName NVARCHAR(512),
            @FullPath NVARCHAR(1000),
            @rc       INT,
            @Total    INT = 0,
            @Ok       INT = 0,
            @Skipped  INT = 0,
            @Failed   INT = 0,
            @Msg      NVARCHAR(2000);

    SET @Folder = CASE WHEN RIGHT(@FolderPath, 1) IN (N'\', N'/') THEN @FolderPath ELSE @FolderPath + N'\' END;

    /* ---- 1. List files in the folder (level 1, files included) ---- */
    CREATE TABLE #Files (Id INT IDENTITY(1,1), FileName NVARCHAR(512), Depth INT, IsFile BIT);

    BEGIN TRY
        INSERT INTO #Files (FileName, Depth, IsFile)
        EXEC master.sys.xp_dirtree @Folder, 1, 1;
    END TRY
    BEGIN CATCH
        SET @Msg = CONCAT(N'Cannot read folder "', @Folder, N'": ', ERROR_MESSAGE());
        THROW 50002, @Msg, 1;
    END CATCH

    DELETE FROM #Files WHERE IsFile = 0 OR FileName NOT LIKE @FilePattern;

    IF NOT EXISTS (SELECT 1 FROM #Files)
    BEGIN
        SET @Msg = CONCAT(N'No files matching "', @FilePattern, N'" found in "', @Folder, N'".');
        RAISERROR(@Msg, 10, 1) WITH NOWAIT;
        RETURN;
    END

    /* ---- 2. Import each file ---- */
    DECLARE file_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT FileName FROM #Files ORDER BY FileName;

    OPEN file_cursor;
    FETCH NEXT FROM file_cursor INTO @FileName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @FullPath = @Folder + @FileName;
        SET @Total += 1;

        EXEC @rc = dbo.ImportEmployeeXmlFile
                   @FilePath        = @FullPath,
                   @ReplaceExisting = @ReplaceExisting,
                   @RunID           = @RunID;

        IF      @rc = 0 SET @Ok      += 1;
        ELSE IF @rc = 1 SET @Skipped += 1;
        ELSE            SET @Failed  += 1;

        SET @Msg = CONCAT(N'[', @Total, N'] ', @FileName, N' -> ',
                          CASE @rc WHEN 0 THEN N'OK' WHEN 1 THEN N'SKIPPED' ELSE N'FAILED' END);
        RAISERROR(@Msg, 0, 1) WITH NOWAIT;

        IF @rc = 2 AND @StopOnError = 1 BREAK;

        FETCH NEXT FROM file_cursor INTO @FileName;
    END

    CLOSE file_cursor;
    DEALLOCATE file_cursor;
    DROP TABLE #Files;

    /* ---- 3. Report ---- */
    SELECT  LogID, FilePath, EmployeeNo, Status, RowsInserted, Message, ErrorNumber, LoggedAt
    FROM    dbo.ImportLog
    WHERE   RunID = @RunID
    ORDER BY LogID;

    SELECT  RunID = @RunID, FilesFound = @Total, Imported = @Ok, Skipped = @Skipped, Failed = @Failed;
END
GO
