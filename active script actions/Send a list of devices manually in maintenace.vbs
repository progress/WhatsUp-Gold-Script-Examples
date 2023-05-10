'Send a list of devices manually in maintenace 
' This active script action queries the database for devices in maintenance mode and the time at which they
' were put into maintenance mode. It then emails it out using SMTP (Note, your SMTP settings will be different)

' Note: This example is provided as an illustration only and is not supported.
' Technical support is available for the Context object, SNMP API, and scripting environment, 
' but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
' For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
' or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

Option Explicit
'*****************Configuration
'E-mail settings
Const SMTPServer = "smtp.yourcompany.com" 'Enter your SMTP info here
Const SMTPSSL = False 'To use SSL, set to true
Const SMTPPort = 25 'SMTP port usually 25, 465, or 587 
Const bRequireAuth = 0 '0 for no authentication, 1 for basic authentication
Const SMTPLogon = "" 'Username: Only used when bRequireAuth is set to 1
Const SMTPPassword = "" 'Password: Only used when bRequireAuth is set to 1
Dim sPriority : sPriority = 1 '1 for normal, 2 for high
Dim sMailFrom : sMailFrom = "youremail@email.com" 'This email should match the SMTPLogon if used
Dim sMailTo : sMailTo = "thatemail@email.com"
' *** End Configuration
Dim oDB : Set oDB = Context.GetDB 'Create DB object
Dim sMessage : sMessage = ""
Dim nCount : nCount = 0

Dim sSql : sSql = "SELECT Distinct D.sDisplayName, MAX(dStartTime) as StartTime, Count(DISTINCT sDisplayName) as Count FROM MonitorState MS " & _
"JOIN Device D ON D.nWorstStateID = MS.nMonitorStateID " & _
"JOIN PivotActiveMonitorTypeToDevice PAMTD ON D.nDeviceID = PAMTD.nDeviceID " & _
"JOIN ActiveMonitorStateChangeLog AMSCL ON PAMTD.nPivotActiveMonitorTypeToDeviceID = AMSCL.nPivotActiveMonitorTypeToDeviceID " & _
"WHERE PAMTD.nMonitorStateID IN (4) AND D.bManualMaintenanceMode IN (1) Group By sDisplayname Order By StartTime"

' *** Execute SQL to get info
Dim oRS: Set oRS = oDB.Execute(sSql)

If Not oRS.EOF Then
 oRS.MoveFirst
 If Not oRS.EOF Then
  sMessage = sMessage & "The following WhatsUp devices are in maintenace mode: " & VbCrLf & vbCrLf
  Do While Not oRS.EOF
   sMessage = sMessage & oRS("sDisplayName") & vbTab & "Since: " & oRS("StartTime") & vbCrLf
   nCount = nCount + oRS("Count")
   oRS.MoveNext
  Loop
  sMessage = sMessage & vbCrLf
  End If
End If

Dim sSubject : sSubject = "WhatsUp has " & nCount & " devices in maintenance mode!"
If nCount <> 0 Then 'only send email is count is does not equal 0
 SendEmail sMailFrom, sMailTo, sSubject, sBody
End If

SendEmail sEmailFrom, sEmailTo, sSubject, sMessage

'Set the result code of the check (0=Success, 1=Error)
Context.SetResult 0, "No error"

Sub SendEmail(sEmailFrom, sEmailTo, sSubject, sBody)
  Dim oEmail : Set oEmail = CreateObject("CDO.Message")
  oEmail.From = sEmailFrom
  oEmail.To = sEmailTo
  oEmail.Subject = sSubject
  oEmail.TextBody = sBody
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