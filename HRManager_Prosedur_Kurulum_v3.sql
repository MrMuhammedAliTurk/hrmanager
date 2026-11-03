/*
    HRManagerDB - Stored Procedure kurulum v3
    Bu script yalnizca uc stored procedure nesnesini olusturur/gunceller.
    Tablolari, VIEW nesnelerini veya mevcut personel/izin/maas verilerini silmez.

    On kosul: HRManagerDB icinde Employees, SalaryHistory, LeaveTypes ve LeaveRequests
    tablolarinin mevcut olmasi gerekir.

    SSMS: Dosyanin tamamini acin ve F5 ile calistirin.
*/
USE HRManagerDB;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.Employees', N'U') IS NULL
   OR OBJECT_ID(N'dbo.SalaryHistory', N'U') IS NULL
   OR OBJECT_ID(N'dbo.LeaveTypes', N'U') IS NULL
   OR OBJECT_ID(N'dbo.LeaveRequests', N'U') IS NULL
BEGIN
    THROW 51990, N'Gerekli HRManagerDB tablolari bulunamadi. Once ana veri tabani kurulumunu kontrol edin.', 1;
END;
GO

/* Eski/yarim olusmus prosedurleri varsa yalnizca prosedur nesnesini kaldir. */
IF OBJECT_ID(N'dbo.sp_AddSalaryChange', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddSalaryChange;
GO
IF OBJECT_ID(N'dbo.sp_SubmitLeaveRequest', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SubmitLeaveRequest;
GO
IF OBJECT_ID(N'dbo.sp_ProcessLeaveRequest', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProcessLeaveRequest;
GO

/* 1. Personelin maasinda tarihceli degisiklik yapar. */
CREATE PROCEDURE dbo.sp_AddSalaryChange
    @EmployeeNumber VARCHAR(10),
    @NewSalary DECIMAL(12,2),
    @EffectiveFrom DATE = NULL,
    @ChangeReason NVARCHAR(200) = N'Maas degisikligi'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@EmployeeNumber)), '') IS NULL
    BEGIN
        THROW 51000, N'Personel numarasi zorunludur.', 1;
    END;

    IF @NewSalary IS NULL OR @NewSalary <= 0
    BEGIN
        THROW 51001, N'Maas sifirdan buyuk olmalidir.', 1;
    END;

    SET @EffectiveFrom = COALESCE(@EffectiveFrom, CONVERT(DATE, GETDATE()));

    DECLARE @EmployeeID INT;
    DECLARE @CurrentSalaryHistoryID INT;
    DECLARE @CurrentEffectiveFrom DATE;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @EmployeeID = e.EmployeeID
        FROM dbo.Employees AS e WITH (UPDLOCK, HOLDLOCK)
        WHERE e.EmployeeNumber = @EmployeeNumber;

        IF @EmployeeID IS NULL
        BEGIN
            THROW 51002, N'Belirtilen personel numarasi bulunamadi.', 1;
        END;

        SELECT TOP (1)
            @CurrentSalaryHistoryID = sh.SalaryHistoryID,
            @CurrentEffectiveFrom = sh.EffectiveFrom
        FROM dbo.SalaryHistory AS sh WITH (UPDLOCK, HOLDLOCK)
        WHERE sh.EmployeeID = @EmployeeID
          AND sh.EffectiveTo IS NULL
        ORDER BY sh.EffectiveFrom DESC;

        IF @CurrentEffectiveFrom IS NOT NULL AND @EffectiveFrom <= @CurrentEffectiveFrom
        BEGIN
            THROW 51003, N'Yeni maas baslangic tarihi mevcut maas baslangicindan sonra olmalidir.', 1;
        END;

        IF @CurrentSalaryHistoryID IS NOT NULL
        BEGIN
            UPDATE dbo.SalaryHistory
            SET EffectiveTo = DATEADD(DAY, -1, @EffectiveFrom)
            WHERE SalaryHistoryID = @CurrentSalaryHistoryID;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.SalaryHistory AS sh WITH (UPDLOCK, HOLDLOCK)
            WHERE sh.EmployeeID = @EmployeeID
              AND @EffectiveFrom >= sh.EffectiveFrom
              AND @EffectiveFrom <= COALESCE(sh.EffectiveTo, CONVERT(DATE, '99991231'))
        )
        BEGIN
            THROW 51004, N'Belirtilen tarih mevcut maas donemlerinden biriyle cakismaktadir.', 1;
        END;

        INSERT INTO dbo.SalaryHistory
            (EmployeeID, SalaryAmount, EffectiveFrom, EffectiveTo, ChangeReason)
        VALUES
            (@EmployeeID, @NewSalary, @EffectiveFrom, NULL, COALESCE(@ChangeReason, N'Maas degisikligi'));

        COMMIT TRANSACTION;

        SELECT N'Maas degisikligi basariyla kaydedildi.' AS ResultMessage,
               @EmployeeNumber AS EmployeeNumber,
               @NewSalary AS NewSalary,
               @EffectiveFrom AS EffectiveFrom;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ;THROW;
    END CATCH;
END;
GO

/* 2. Aktif personel icin cakisma kontrolu yaparak izin talebi acar. */
CREATE PROCEDURE dbo.sp_SubmitLeaveRequest
    @EmployeeNumber VARCHAR(10),
    @LeaveTypeName NVARCHAR(80),
    @StartDate DATE,
    @EndDate DATE,
    @EmployeeNote NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@EmployeeNumber)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(@LeaveTypeName)), '') IS NULL
       OR @StartDate IS NULL
       OR @EndDate IS NULL
    BEGIN
        THROW 51100, N'Personel, izin turu, baslangic ve bitis tarihleri zorunludur.', 1;
    END;

    IF @EndDate < @StartDate
    BEGIN
        THROW 51101, N'Izin bitis tarihi baslangic tarihinden once olamaz.', 1;
    END;

    IF @StartDate < CONVERT(DATE, GETDATE())
    BEGIN
        THROW 51102, N'Izin baslangic tarihi bugun veya daha sonrasi olmalidir.', 1;
    END;

    DECLARE @EmployeeID INT;
    DECLARE @LeaveTypeID INT;
    DECLARE @NewLeaveRequestID INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @EmployeeID = e.EmployeeID
        FROM dbo.Employees AS e WITH (UPDLOCK, HOLDLOCK)
        WHERE e.EmployeeNumber = @EmployeeNumber
          AND e.EmploymentStatus = 'Active';

        IF @EmployeeID IS NULL
        BEGIN
            THROW 51103, N'Aktif personel bulunamadi.', 1;
        END;

        SELECT @LeaveTypeID = lt.LeaveTypeID
        FROM dbo.LeaveTypes AS lt
        WHERE lt.LeaveTypeName = @LeaveTypeName
          AND lt.IsActive = 1;

        IF @LeaveTypeID IS NULL
        BEGIN
            THROW 51104, N'Aktif izin turu bulunamadi.', 1;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.LeaveRequests AS lr WITH (UPDLOCK, HOLDLOCK)
            WHERE lr.EmployeeID = @EmployeeID
              AND lr.RequestStatus IN ('Pending', 'Approved')
              AND @StartDate <= lr.EndDate
              AND @EndDate >= lr.StartDate
        )
        BEGIN
            THROW 51105, N'Izin tarihleri mevcut bekleyen veya onaylanmis bir taleple cakismaktadir.', 1;
        END;

        INSERT INTO dbo.LeaveRequests
            (EmployeeID, LeaveTypeID, StartDate, EndDate, EmployeeNote)
        VALUES
            (@EmployeeID, @LeaveTypeID, @StartDate, @EndDate, @EmployeeNote);

        SET @NewLeaveRequestID = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

        SELECT @NewLeaveRequestID AS NewLeaveRequestID,
               N'Izin talebi olusturuldu ve yonetici onayini bekliyor.' AS ResultMessage;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ;THROW;
    END CATCH;
END;
GO

/* 3. Izin talebini yalnizca dogrudan yoneticisinin karara baglamasini saglar. */
CREATE PROCEDURE dbo.sp_ProcessLeaveRequest
    @LeaveRequestID INT,
    @ApproverEmployeeNumber VARCHAR(10),
    @Decision VARCHAR(10),
    @DecisionNote NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @LeaveRequestID IS NULL OR @LeaveRequestID <= 0
    BEGIN
        THROW 51200, N'Gecerli bir izin talep numarasi girilmelidir.', 1;
    END;

    IF @Decision IS NULL OR @Decision NOT IN ('Approved', 'Rejected')
    BEGIN
        THROW 51201, N'Karar Approved veya Rejected olmalidir.', 1;
    END;

    IF NULLIF(LTRIM(RTRIM(@ApproverEmployeeNumber)), '') IS NULL
    BEGIN
        THROW 51206, N'Onaylayici personel numarasi zorunludur.', 1;
    END;

    DECLARE @RequesterID INT;
    DECLARE @ManagerID INT;
    DECLARE @ApproverID INT;
    DECLARE @CurrentStatus VARCHAR(20);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @RequesterID = e.EmployeeID,
            @ManagerID = e.ManagerID,
            @CurrentStatus = lr.RequestStatus
        FROM dbo.LeaveRequests AS lr WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Employees AS e ON e.EmployeeID = lr.EmployeeID
        WHERE lr.LeaveRequestID = @LeaveRequestID;

        IF @RequesterID IS NULL
        BEGIN
            THROW 51202, N'Izin talebi bulunamadi.', 1;
        END;

        IF @CurrentStatus <> 'Pending'
        BEGIN
            THROW 51203, N'Yalnizca Pending durumundaki talepler karara baglanabilir.', 1;
        END;

        SELECT @ApproverID = e.EmployeeID
        FROM dbo.Employees AS e
        WHERE e.EmployeeNumber = @ApproverEmployeeNumber
          AND e.EmploymentStatus = 'Active';

        IF @ApproverID IS NULL
        BEGIN
            THROW 51204, N'Aktif onaylayici bulunamadi.', 1;
        END;

        IF @ManagerID IS NULL OR @ManagerID <> @ApproverID
        BEGIN
            THROW 51205, N'Izin talebini yalnizca calisanin dogrudan yoneticisi karara baglayabilir.', 1;
        END;

        UPDATE dbo.LeaveRequests
        SET RequestStatus = @Decision,
            ApprovedByEmployeeID = @ApproverID,
            DecisionDate = SYSDATETIME(),
            DecisionNote = @DecisionNote
        WHERE LeaveRequestID = @LeaveRequestID;

        COMMIT TRANSACTION;

        SELECT N'Izin talebi basariyla guncellendi.' AS ResultMessage,
               @LeaveRequestID AS LeaveRequestID,
               @Decision AS NewStatus;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ;THROW;
    END CATCH;
END;
GO

/* Kurulum dogrulamasi: uc prosedur de listelenmelidir. */
SELECT
    p.name AS ProsedurAdi,
    SCHEMA_NAME(p.schema_id) AS Semasi,
    p.create_date AS OlusturulmaTarihi,
    p.modify_date AS SonDegisiklik
FROM sys.procedures AS p
WHERE p.name IN
(
    N'sp_AddSalaryChange',
    N'sp_SubmitLeaveRequest',
    N'sp_ProcessLeaveRequest'
)
ORDER BY p.name;

SELECT COUNT(*) AS OlusturulanHRManagerProsedurSayisi
FROM sys.procedures AS p
WHERE p.name IN
(
    N'sp_AddSalaryChange',
    N'sp_SubmitLeaveRequest',
    N'sp_ProcessLeaveRequest'
);
GO
