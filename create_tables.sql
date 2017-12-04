USE [CA_UIM]
GO

/****** Object: DROP Table [dbo].[Audit_Hubs] ******/
EXEC sys.sp_dropextendedproperty @name=N'MS_Description' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Hubs'
GO

ALTER TABLE [dbo].[Audit_Hubs] DROP CONSTRAINT [DF_Audit_Hubs_timetamp]
GO

DROP TABLE [dbo].[Audit_Hubs]
GO

/****** Object: DROP Table [dbo].[Audit_Robots] ******/
EXEC sys.sp_dropextendedproperty @name=N'MS_Description' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Robots'
GO

ALTER TABLE [dbo].[Audit_Robots] DROP CONSTRAINT [FK_Audit_Robots_Audit_Hubs]
GO

ALTER TABLE [dbo].[Audit_Robots] DROP CONSTRAINT [DF_Audit_Robots_timetamp]
GO

DROP TABLE [dbo].[Audit_Robots]
GO

/****** Object: DROP Table [dbo].[Audit_Probes] ******/
EXEC sys.sp_dropextendedproperty @name=N'MS_Description' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Probes'
GO

ALTER TABLE [dbo].[Audit_Probes] DROP CONSTRAINT [FK_Audit_Probes_Audit_Robots]
GO

ALTER TABLE [dbo].[Audit_Probes] DROP CONSTRAINT [DF_Audit_Probes_timetamp]
GO

DROP TABLE [dbo].[Audit_Probes]
GO

/****** Object: DROP Table [dbo].[Audit_Probes_Attr] ******/
EXEC sys.sp_dropextendedproperty @name=N'MS_Description' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Probes_Attr'
GO

ALTER TABLE [dbo].[Audit_Probes_Attr] DROP CONSTRAINT [FK_Audit_Probes_Attr_Audit_Probes]
GO

DROP TABLE [dbo].[Audit_Probes_Attr]
GO

/****** Object: COMMON ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****** Object: CREATE Table [dbo].[Audit_Hubs] ******/
CREATE TABLE [dbo].[Audit_Hubs](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[domain] [varchar](255) NOT NULL,
	[name] [varchar](255) NOT NULL,
	[robot] [varchar](255) NOT NULL,
	[ip] [varchar](255) NOT NULL,
	[port] [varchar](255) NULL,
	[version] [varchar](255) NOT NULL,
	[origin] [varchar](255) NOT NULL,
	[create_time] [datetime] NOT NULL,
	[change_time] [datetime] NULL,
 CONSTRAINT [PK_Audit_Hubs] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[Audit_Hubs] ADD  CONSTRAINT [DF_Audit_Hubs_timetamp]  DEFAULT (getdate()) FOR [create_time]
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Audit - List of Hubs' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Hubs'
GO

/****** Object: CREATE Table [dbo].[Audit_Robots] ******/
CREATE TABLE [dbo].[Audit_Robots](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[hub_id] [int] NOT NULL,
	[domain] [varchar](255) NOT NULL,
	[name] [varchar](255) NOT NULL,
	[status] [int] NOT NULL,
	[ip] [varchar](255) NOT NULL,
	[version] [varchar](255) NOT NULL,
	[origin] [varchar](255) NOT NULL,
	[create_time] [datetime] NOT NULL,
	[change_time] [datetime] NULL,
 CONSTRAINT [PK_Audit_Robots] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[Audit_Robots] ADD  CONSTRAINT [DF_Audit_Robots_timetamp]  DEFAULT (getdate()) FOR [create_time]
GO

ALTER TABLE [dbo].[Audit_Robots]  WITH CHECK ADD  CONSTRAINT [FK_Audit_Robots_Audit_Hubs] FOREIGN KEY([hub_id])
REFERENCES [dbo].[Audit_Hubs] ([id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[Audit_Robots] CHECK CONSTRAINT [FK_Audit_Robots_Audit_Hubs]
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Audit - List of Robots' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Robots'
GO

/****** Object: CREATE Table [dbo].[Audit_Probes] ******/
CREATE TABLE [dbo].[Audit_Probes](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[robot_id] [int] NOT NULL,
	[name] [varchar](255) NOT NULL,
	[active] [int] NOT NULL,
	[version] [varchar](255) NOT NULL,
	[build] [varchar](255) NOT NULL,
	[process_state] [varchar](255) NOT NULL,
	[create_time] [datetime] NOT NULL,
	[change_time] [datetime] NULL,
 CONSTRAINT [PK_Audit_Probes] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[Audit_Probes] ADD  CONSTRAINT [DF_Audit_Probes_timetamp]  DEFAULT (getdate()) FOR [create_time]
GO

ALTER TABLE [dbo].[Audit_Probes]  WITH CHECK ADD  CONSTRAINT [FK_Audit_Probes_Audit_Robots] FOREIGN KEY([robot_id])
REFERENCES [dbo].[Audit_Robots] ([id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[Audit_Probes] CHECK CONSTRAINT [FK_Audit_Probes_Audit_Robots]
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Audit - List of Probes' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Probes'
GO

/****** Object: CREATE Table [dbo].[Audit_Probes_Attr] ******/
CREATE TABLE [dbo].[Audit_Probes_Attr](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[probe_id] [int] NOT NULL,
	[cfg_key] [varchar](255) NOT NULL,
	[cfg_value] [varchar](255) NULL,
 CONSTRAINT [PK_Audit_Probes_Attr] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[Audit_Probes_Attr]  WITH CHECK ADD  CONSTRAINT [FK_Audit_Probes_Attr_Audit_Probes] FOREIGN KEY([probe_id])
REFERENCES [dbo].[Audit_Probes] ([id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[Audit_Probes_Attr] CHECK CONSTRAINT [FK_Audit_Probes_Attr_Audit_Probes]
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Audit - List of Probes Attributes' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Audit_Probes_Attr'
GO
