'Send SQL Query results in an email
' This active script action queries the database for using your specified settings and then
' emails the query results as a HTML table.

' Note: This example is provided as an illustration only and is not supported.
' Technical support is available for the Context object, SNMP API, and scripting environment, 
' but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
' For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
' or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

Option Explicit
'''''''''''''''''
' Configuration '
'''''''''''''''''
'E-mail settings
Const SMTPServer = "smtp.yourcompany.com"
Const SMTPSSL = True 'To use SSL, set to true
Const SMTPPort = 465 'SMTP port, 25 (default) or 465 (SSL) or 587 (TLS)
'***IF USING AUTHENTICATION, SMTPLogon and sMailFrom MUST BE IDENTICAL!***
Const bRequireAuth = 1 '0 for no authentication, 1 for basic authentication
'***IF USING AUTHENTICATION, SMTPLogon and sMailFrom MUST BE IDENTICAL!***
Const SMTPLogon = "mylogin@yourcompany.com" 'Username: Only used when bRequireAuth is set to 1
Const SMTPPassword = "I am sharing this password." 'Password: Only used when bRequireAuth is set to 1
'***Caution: Any one with access to edit scripts in WhatsUp Gold can see this information in plain text!**
Dim sPriority : sPriority = 1 '1 for normal, 2 for high
Dim sMailFrom : sMailFrom = "mylogin@yourcompany.com"
Dim sMailTo : sMailTo = "youremail@yourcompany.com"
Dim sSubject : sSubject = "SQL Query Results: Credential Failure Check" 'Put the subject of your e-mail here
Dim sSaveFile : sSaveFile = "C:\temp\sqlquery.htm" 'Where to save the HTML file with the results table
'Database settings
'You can change this to call/query *ANY* database
'***Caution: Any one with access to edit scripts in WhatsUp Gold can see this information in plain text!**
Dim sADODriver : sADODriver = "{SQL Server}" 'Name of the driver to use for the ADODB connection
Dim sdbHost : sdbHost= "localhost" ' Hostname of the database server
Dim sdbName : sdbName = "WhatsUp"' Name of the database/SID
Dim sdbUser : sdbUser = "sa" ' Name of the ADO user
Dim sdbPass : sdbPass = "WhatsUp_Gold" ' Password of the above-named user

'The sample query looks at the WhatsUp Gold logs to see if there are any credential failures in the past 24 hours
Dim sSql1 : sSql1 = "select sDisplayName, dDateTime as 'dStartTime', Null as 'dEndTime', sDetails as 'Details', 'Performance' as 'MonitorType' from StatisticalMonitorLog SML " & _
" join PivotStatisticalMonitorTypeToDevice PSMTTD on PSMTTD.nPivotStatisticalMonitorTypeToDeviceID = SML.nPivotStatisticalMonitorTypeToDeviceID " & _
" join Device D on D.nDeviceID = PSMTTD.nDeviceID where (sDetails like '%\root\cimv2%' or sDetails like '%credential%' or sDetails like '%access%') and " & _
" DateDiff(DAY, dDateTime, GetDate()) < 1 " & _
" union " & _
" select sDisplayName, dStartTime, dEndTime, sResult as 'Details', 'Active' as 'MonitorType' from ActiveMonitorStateChangeLog AMSCL " & _
" join PivotActiveMonitorTypeToDevice PAMTD on PAMTD.nPivotActiveMonitorTypeToDeviceID = AMSCL.nPivotActiveMonitorTypeToDeviceID " & _
" join Device D on D.nDeviceID = PAMTD.nDeviceID " & _
" where ((sResult like '%\root\cimv2%' or sResult like '%credential%' or sResult like '%access%') and (DateDiff(DAY, dStartTime, GetDate()) < 1 or DateDiff(DAY, dEndTime, GetDate()) < 1)) " & _
" union " & _
" select sDisplayName, dDateTime as 'dStartTime', Null as 'dEndTime', sDetails as 'Details', 'Passive' as 'MonitorType' from PassiveMonitorErrorLog PMEL " & _
" join PivotPassiveMonitorTypeToDevice PPMTD on PPMTD.nPivotPassiveMonitorTypeToDeviceID = PMEL.nPivotPassiveMonitorTypeToDeviceID " & _
" join Device D on D.nDeviceID = PPMTD.nDeviceId " & _
" where ((sDetails like '%user%' or sDetails like '%credential%' or sDetails like '%access%') and (DateDiff(DAY, dDateTime, GetDate()) < 1)) " & _
" order by dDateTime desc" 'Put your select statement here

'Variables and constants
Const adOpenStatic = 3
Const adLockOptimistic = 3
Dim oConnection, oRS, oFSO, fOut, i, oDB
Set oConnection = CreateObject("ADODB.Connection")
Set oRS = CreateObject("ADODB.Recordset")
Set oFSO = CreateObject("Scripting.FileSystemObject")
Set fOut = oFSO.CreateTextFile(sSaveFile, True)

'Open connection using connection string below and run query
oConnection.Open("Driver=" & sADODriver & ";Server=" & sdbHost & ";Database=" & sdbName & ";Uid=" & sdbUser & ";Pwd=" & sdbPass & ";")
oRS.Open sSql1, oConnection, adOpenStatic, adLockOptimistic

'Parse query results to table in .htm file
If Not oRS.EOF Then
 oRS.MoveFirst
 If Not oRS.EOF Then
  fOut.WriteLine "<html>"
  fOut.WriteLine "  <head>"
  fOut.WriteLine "    <title>SQL Query Results</title>"
  fOut.WriteLine "    <style>"
  fOut.WriteLine "      table { border-collapse: collapse;}"
  fOut.WriteLine "      th { font-family:Calibri; font-size:11pt; border: 1px solid black;}"
  fOut.WriteLine "      td { font-family:Calibri; font-size:11pt; border: 1px solid black;}"
  fOut.WriteLine "    </style>"
  fOut.WriteLine "  </head>"
  fOut.WriteLine "<body>"
  fOut.WriteLine "  <table>"
  fOut.WriteLine "    <tr>"
  'Header row
  For i = 0 To oRS.Fields.Count -1
    fOut.WriteLine "      <th nowrap>" & oRS.Fields(i).Name & "</th>"
    Context.NotifyProgress oRS.Fields(i).Name
  Next
  fOut.WriteLine "    </tr>"
  Do While Not oRS.EOF
   fOut.WriteLine "    <tr>"
  'Values
   For i = 0 To oRS.Fields.Count -1
    fOut.WriteLine "      <td nowrap>" & oRS.Fields(i).Value & "</td>"
    Context.NotifyProgress " " & oRS.Fields(i).Value
   Next
   fOut.WriteLine "    </tr>"
   oRS.MoveNext
  Loop
  fOut.WriteLine "  </table>"

  Dim oEmail
  SendEmail sMailFrom, sMailTo, sSubject, sSaveFile
  End If
End If

oRS.Close
oConnection.Close

Sub SendEmail(sEmailFrom, sEmailTo, sSubject, sSaveFile)
  Dim oEmail : Set oEmail = CreateObject("CDO.Message")
  oEmail.From = sEmailFrom
  oEmail.To = sEmailTo
  oEmail.Subject = sSubject
  oEmail.CreateMHTMLBody "file://"&sSaveFile
  oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2
  oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserver") = SMTPServer
  oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = bRequireAuth
  If sPriority = 2 Then
   oEmail.Fields.Item("urn:schemas:mailheader:X-MSMail-Priority") = "High"
   oEmail.Fields.Item("urn:schemas:mailheader:X-Priority") = 2
   oEmail.Fields.Item("urn:schemas:httpmail:importance") = 2
   oEmail.Fields.Update
  End If
  If bRequireAuth <> 0 Then
   oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusername") = SMTPLogon
   oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendpassword") = SMTPPassword
  End If
   oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserverport") = SMTPPort
   oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpusessl") = SMTPSSL
  oEmail.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpconnectiontimeout") = 60
  oEmail.Configuration.Fields.Update
  oEmail.Send
  Set oEmail = Nothing
End Sub

'Set the result code of the check (0=Success, 1=Error)
Context.SetResult 0, "No error"