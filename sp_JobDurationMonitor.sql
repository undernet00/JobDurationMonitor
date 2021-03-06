USE [DBTools]
GO
 
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- ==============================================
-- Author:		Martin Rivero and Gary Vazquez
-- Create date: 14/07/2021
-- Description:	Detects jobs that take too much 
--				time to finish. 
--				These can be configured with the
--				max amount of time in minutes 
--				and if the job should be stopped.
-- ==============================================

ALTER PROCEDURE [dbo].[sp_JobDurationMonitor]
AS
BEGIN
	SET NOCOUNT ON

	--EXEC sp_JobDurationMonitor
	IF OBJECT_ID(N'#JobsCorriendo', N'U') IS NOT NULL
		DROP TABLE #JobsCorriendo;

	SELECT *
	INTO #JobsCorriendo
	FROM DBTools.dbo.v_jobscorriendo

	--Jobs que demoran más del máximo configurado en DBTools.dbo.Jobs
	IF OBJECT_ID(N'#JobsParaReportar', N'U') IS NOT NULL
		DROP TABLE #JobsParaReportar;

	--Jobs para reportar demoras por mail
	SELECT jc.spid
		,jc.job_name
		,jc.minutos
		,j.TiempoMaxMinutos
		,j.Detener
	INTO #JobsParaReportar
	FROM #JobsCorriendo jc
	LEFT JOIN DBTools.dbo.Jobs j ON jc.job_name = j.NombreJob
	WHERE (
			jc.minutos > j.TiempoMaxMinutos
			AND j.NombreJob IS NOT NULL
			) --Jobs registrados con máximos registrados 
		OR (
			jc.minutos > (
				SELECT TiempoMaxMinutos
				FROM DBTools.dbo.Jobs
				WHERE NombreJob = '(TODOS)'
				)
			AND j.NombreJob IS NULL
			) --Jobs no registrados que excedan el umbral genérico configurado en (TODOS).

	IF (
			(
				SELECT COUNT(*)
				FROM #JobsParaReportar
				) > 0
			)
	BEGIN
		--Jobs para detener y avisar
		IF OBJECT_ID(N'#JobsParaDetener', N'U') IS NOT NULL
			DROP TABLE #JobsParaDetener;

		SELECT jc.spid
			,jc.job_name
			,jc.minutos
			,j.TiempoMaxMinutos
			,j.Detener
		INTO #JobsParaDetener
		FROM #JobsCorriendo jc
		INNER JOIN DBTools.dbo.Jobs j ON jc.job_name = j.NombreJob
		WHERE jc.minutos > j.TiempoMaxMinutos
			AND j.Detener = 'S'

		--Creo temp para no perder la tabla original y poder reportar
		SELECT *
		INTO #JobsParaDetenerTemp
		FROM #JobsParaDetener

		--Detener
		DECLARE @JobParaDetener VARCHAR(256)
		DECLARE @PidParaDetener INT
		DECLARE @killstatement VARCHAR(15)

		WHILE (
				SELECT COUNT(*)
				FROM #JobsParaDetenerTemp
				) > 0
		BEGIN
			SELECT TOP 1 @JobParaDetener = #JobsParaDetenerTemp.job_name
				,@PidParaDetener = #JobsParaDetenerTemp.spid
			FROM #JobsParaDetenerTemp

			INSERT INTO [mon].[LogMonitoreo] (
				[Mensaje]
				,[SQL]
				,[Fecha]
				,[InvocadoDesde]
				,[Error]
				,[ErrorNumero]
				)
			VALUES (
				'Intentando detener job: ' + @JobParaDetener
				,'EXEC msdb.dbo.sp_stop_job @JobParaDetener'
				,GETDATE()
				,(
					SELECT OBJECT_NAME(@@PROCID)
					)
				,'N'
				,NULL
				)

			-- Agregar control si no es detenido matar proceso. Por Gary Vazquez.
			EXEC msdb.dbo.sp_stop_job @JobParaDetener;

			IF (
					SELECT COUNT(*)
					FROM v_JobsCorriendo
					WHERE v_JobsCorriendo.job_name = @JobParaDetener
					) != 0
			BEGIN
				SET @killstatement = 'KILL ' + cast(@PidParaDetener AS VARCHAR(3))

				EXEC (@killstatement)
			END

			INSERT INTO [mon].[LogMonitoreo] (
				[Mensaje]
				,[SQL]
				,[Fecha]
				,[InvocadoDesde]
				,[Error]
				,[ErrorNumero]
				)
			VALUES (
				'Se detuvo job: ' + @JobParaDetener
				,'EXEC msdb.dbo.sp_stop_job @JobParaDetener'
				,GETDATE()
				,(
					SELECT OBJECT_NAME(@@PROCID)
					)
				,'N'
				,NULL
				)

			DELETE #JobsParaDetenerTemp
			WHERE #JobsParaDetenerTemp.job_name = @JobParaDetener
		END

		--Informar
		DECLARE @Body1 VARCHAR(MAX)
		DECLARE @Asunto NVARCHAR(MAX)

		--JOBS que demoran MAIL
		SET @Body1 = '<P align="center" style="font-family: Lucida Console, Monaco, monospace;font-size: 1.50em;" >Jobs Que Demoran </P>'
		SET @body1 = @body1 + '<table align="center" cellpadding="15" cellspacing="0" style="color: #666666; border-radius: 5px; letter-spacing: 1.50px;
							text-align:center; border: 1px solid lightgrey; font-family: Lucida Console, Monaco, monospace;">' + '<tr style="font-size: 0.90em">
							<th style=" background-color: #d9d9d9;">Nombre</th>
							<th style=" background-color: #d9d9d9;">Tiempo (mins.)</th>
							<th style=" background-color: #d9d9d9;">Máximo (mins.)</th>
							<th style=" background-color: #d9d9d9;">Detener si excede</th>					
							</tr>'

		SELECT @body1 = @body1 + '<tr style="font-size: 1.00em;">' + '<td style=" background-color: #cccccc; border-bottom: 1px solid #BDBDBD; color: white;">' + jr.job_name + '</td>' + '<td style=" background-color: #e6e6e6; text-align: center; border-bottom: 1px solid #d9d9d9;">' + CAST(jr.minutos AS VARCHAR) + '</td>' + '<td style=" background-color: #e6e6e6; text-align: center; border-bottom: 1px solid #d9d9d9;">' + CAST(COALESCE(jr.TiempoMaxMinutos, - 1) AS VARCHAR) + '</td>' + CASE 
				WHEN (jr.Detener IS NULL)
					THEN '<td style=" background-color: #E3D545; padding-left: 30px; color: white;">N/A</td>'
				WHEN (jr.Detener = 'S') --rojo
					THEN '<td style=" background-color: #EF5350; padding-left: 30px; color: white;">' + jr.detener + '</td>'
				WHEN (jr.Detener = 'N') --Normal
					THEN '<td style=" background-color: #E3D545; padding-left: 30px; color: white;">' + jr.detener + '</td>'
				END
		FROM #JobsParaReportar jr
		ORDER BY jr.minutos DESC

		SELECT @body1 = @body1 + '</table>'

		SELECT @Body1 = @Body1 + '<P align="center" style="font-family: Lucida Console, Monaco, monospace;font-size: 1em;" >Los Jobs con la opción "Detener si excede=S" fueron detenidos por el monitor. Puedes configurar el monitor editando la tabla DBTools.dbo.Jobs. Más info <a href = "http://9.39.252.8/mediawiki/index.php/Jobs_que_demoran">aquí</a>." </P>'

		SET @Asunto = 'Jobs SQL Server que demoran'

		--SELECT @Body1
		EXEC msdb.dbo.sp_send_dbmail @Profile_name = 'Mosca'
			,@Body = @body1
			,@Body_format = 'HTML'
			,@Recipients = 'xxxxx@xxxxx.com.uy'
			,
			--@blind_copy_recipients	= 'xxxxx@xxxxx.com.uy',,
			@Subject = @Asunto
	END
			--EXEC dbo.sp_JobDurationMonitor
			--SELECT * FROM DBTools.dbo.v_jobscorriendo
END