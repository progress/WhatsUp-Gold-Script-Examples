'Get SNMP Value and Email it
' This active script action uses the SNMP API to obtain a value and then email it using SMTP

' Note: This example is provided as an illustration only and is not supported.
' Technical support is available for the Context object, SNMP API, and scripting environment, 
' but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
' For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
' or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

Option Explicit
'====================================================
' NAME: Lookup SNMP value and e-mail it
' AUTHOR: Jason Alberino, Ipswitch, Inc.
' DATE: 01/20/2017
'====================================================
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
'SNMP settings
Dim sOID : sOID = "1.3.6.1.4.1.534.1.2.1.0" 'OID to lookup the value of
Dim nSNMPTimeout : nSNMPTimeout = 3000 'Set ms for SNMP timeouts
Dim nSNMPRetry : nSNMPRetry = 2 'Set the number of SNMP retries
'****************End Configuration
'Get Device details
Dim nDeviceID : nDeviceID = Context.GetProperty("DeviceID")
Dim sNetworkName : sNetworkName = Context.GetProperty("Name")
Dim sDisplayName : sDisplayName = Context.GetProperty("DisplayName")
Dim sActiveMonitorName : sActiveMonitorName = "%ActiveMonitor.Name"
Dim sActiveMonitorState : sActiveMonitorState = "%ActiveMonitor.State"

'Create SNMP object
Dim oSnmp : Set oSnmp = CreateObject("CoreAsp.SnmpRqst")
Dim nTimeout : nTimeout = oSnmp.SetTimeoutMs(nSNMPTimeout)
Dim nRetries : nRetries = oSnmp.SetNumRetries(nSNMPRetry)
'Initialize and Test SNMP Connection
Dim bSNMPResult : bSNMPResult = 0
Dim bFail : bFail = 0
Dim sValue
Set rc = oSnmp.Initialize(nDeviceID)
If rc.Failed Then
 sErrorMsg = rc.GetErrorMsg
 bSNMPResult = 1
Else
 Set rc = oSnmp.Get(sOID)
 If rc.Failed Then
  sErrorMsg = rc.GetErrorMsg
  bFail = 1
 Else
  sValue = rc.GetValue
  Context.NotifyProgress sOID & " has a value of " & sValue
 End If
End If
'Set the subject line here
Dim sSubject : sSubject = "(" & sDisplayName & ")" & sActiveMonitorName & " is " & sActiveMonitorState
'Set the message body here
Dim sBody : sBody = "The value of " & sOID & " is " & sValue

If bSNMPResult = 0 And bFail = 0 Then
 SendEmail sMailFrom, sMailTo, sSubject, sBody
End If

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