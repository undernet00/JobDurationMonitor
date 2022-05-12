USE [DBTools]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE VIEW [dbo].[v_JobsCorriendo]
AS
SELECT       m.spid, ja.job_id, j.name AS job_name, ja.start_execution_date, DATEDIFF(minute, ja.start_execution_date, GETDATE()) AS minutos, ISNULL(ja.last_executed_step_id, 0) + 1 AS current_executed_step_id, js.step_name
FROM					v_Monitoreo1 m,
						msdb.dbo.sysjobactivity AS ja LEFT OUTER JOIN
                         msdb.dbo.sysjobhistory AS jh ON ja.job_history_id = jh.instance_id INNER JOIN
                         msdb.dbo.sysjobs AS j ON ja.job_id = j.job_id INNER JOIN
                         msdb.dbo.sysjobsteps AS js ON ja.job_id = js.job_id AND ISNULL(ja.last_executed_step_id, 0) + 1 = js.step_id
WHERE        (ja.session_id =
                             (SELECT        TOP (1) session_id
                               FROM            msdb.dbo.syssessions
                               ORDER BY agent_start_date DESC)) AND (ja.start_execution_date IS NOT NULL) AND (ja.stop_execution_date IS NULL) 
							   
							   and SUBSTRING(cast(ja.job_id as varchar (40)), 25, 30) in (select substring(m.program_name, 52, 12) from v_Monitoreo1) 
							   group by m.spid, ja.job_id, j.name, ja.start_execution_date, DATEDIFF(minute, ja.start_execution_date, GETDATE()), ISNULL(ja.last_executed_step_id, 0) + 1, js.step_name

GO

CREATE TABLE [dbo].[Jobs](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[NombreJob] [varchar](256) NULL,
	[TiempoMaxMinutos] [int] NULL,
	[Detener] [char](1) NULL,
 CONSTRAINT [PK_Jobs] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
 CONSTRAINT [IX_Unique_NombreJob] UNIQUE NONCLUSTERED 
(
	[NombreJob] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO



CREATE TABLE [mon].[LogMonitoreo](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Mensaje] [varchar](max) NULL,
	[SQL] [varchar](max) NULL,
	[Fecha] [smalldatetime] NULL,
	[InvocadoDesde] [varchar](256) NULL,
	[Error] [char](1) NULL,
	[ErrorNumero] [int] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO



