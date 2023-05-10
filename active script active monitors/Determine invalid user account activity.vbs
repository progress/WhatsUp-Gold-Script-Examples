'Determine invalid user account activity
' Assuming ICMP is not blocked and there's a ping monitor on the device, we want to   
' perform the actual check only if the Ping monitor is up. ConnectServer method of   
' the SWbemLocator has a long time out so it would be good to avoid unnecessary tries.  
' Please note: there's no particular polling order of active monitors on a device.   
' During each polling cycle, it's possible that this monitor could be polled before   
' Ping is polled. If the network connection just goes down but Ping is not polled yet,   
' and therefore still has an up state, this active monitor will still do an actual    
' check and experience a real down. But for the subsequent polls, it won't be doing a  
' real check (ConnectServer won't be called) as Ping monitor has a down state, and this  
' monitor will be assumed down.  

' Note: This example is provided as an illustration only and is not supported.
' Technical support is available for the Context object, SNMP API, and scripting environment, 
' but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
' For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
' or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

sComputer = Context.GetProperty("Address")  
nDeviceID = Context.GetProperty("DeviceID")  

If IsPingUp(nDeviceID) = false Then  
    Context.SetResult 1,"Actual check was not performed due to ping being down. Automatically set to down."  
Else  
    sAdminName = Context.GetProperty("CredWindows:DomainAndUserid")  
    sAdminPasswd = Context.GetProperty("CredWindows:Password")  
    sLoginUser = GetCurrentLoginUser(sComputer, sAdminName, sAdminPasswd)  
    sExpectedUser = "administrator"  
      
    If Not IsNull(sLoginUser) Then  
        If instr(1,sLoginUser, sExpectedUser,1) > 0  Then  
            Context.SetResult 0,"Current login user is " & sLoginUser  
        ElseIf sLoginUser = " " Then  
            Context.SetResult 0,"No one is currently logged in."   
        Else  
            Context.SetResult 1,"an unexpected user " & sLoginUser & " has logged in " & sComputer   
        End If  
    End If  
End If  
  
'Check if Ping monitor on the device specified by nDeviceID is up.  
'If nDeviceID is not available as it's in the case during discovery, then assume  
'ping is up.  
'If ping monitor is not on the device, then assume it's up so the real check will be  
'performed.   
Function IsPingUp(nDeviceID)  
    If nDeviceID > -1 Then   
        'get the Ping monitor up state.  
        sSqlGetUpState = "SELECT sStateName from PivotActiveMonitorTypeToDevice as P join " & _  
        "ActiveMonitorType as A on P.nActiveMonitorTypeID=A.nActiveMonitorTypeID " & _  
        "join MonitorState as M on P.nMonitorStateID = M.nMonitorStateID " & _  
        "where nDeviceID=" & nDeviceID & " and A.sMonitorTypeName='Ping' and " & _  
        " P.bRemoved=0"  
          
        Set oDBconn = Context.GetDB  
        Set oStateRS = CreateObject("ADODB.Recordset")  
        oStateRS.Open sSqlGetUpState,oDBconn,3  
          
        'if recordset is empty then   
        If oStateRS.RecordCount = 1 Then  
            If instr(1,oStateRS("sStateName"),"up",1) > 0 Then  
                IsPingUp = true  
            Else  
                IsPingUP = false  
            End If  
        Else  
            'if there's no ping on the device, then just assume up, so regular check will happen.  
            IsPingUp= true  
        End If  
      
        oStateRS.Close  
        oDBconn.Close  
        Set oStateRS = Nothing  
        Set oDBconn = Nothing  
      
    Else  
        'assume up, since there's no device yet. It's for scanning during discovery.  
        IsPingUP = true  
    End If  
End Function  
      
'Try to get the current login user name.  
Function GetCurrentLoginUser(sComputer, sAdminName, sAdminPasswd)   
    GetCurrentLoginUser=Null  
    Set oSWbemLocator = CreateObject("WbemScripting.SWbemLocator")  
    On Error Resume Next  
    Set oSWbemServices = oSWbemLocator.ConnectServer _  
    (sComputer, "root\cimv2",sAdminName,sAdminPasswd)  
  
    If Err.Number <> 0 Then  
        Context.LogMessage("The 1st try to connect to " & sComputer & " failed. Err:" & Err.Description)  
        Err.Clear        
        'If the specified user name and password for WMI connection failed, then  
        'try to connect without user name and password. Can't specify user name  
        'and password when connecting to local machine.  
        On Error Resume Next  
        Set oSWbemServices = oSWbemLocator.ConnectServer(sComputer, "root\cimv2")  
  
        If Err.Number <> 0 Then  
            Err.Clear  
            On Error Resume Next  
            Context.SetResult 1,"Failed to access " & sComputer & " " & _  
            "using username:" & sAdminName & " password."  & " Err:  " &  Err.Description  
            Exit Function  
        End If  
  
    End If  
      
    Set colSWbemObjectSet = oSWbemServices.InstancesOf("Win32_ComputerSystem")  
      
    For Each oSWbemObject In colSWbemObjectSet  
        On Error Resume Next  
        'Context.SetResult 0,"User Name: " & oSWbemObject.UserName & " at " & sComputer  
        sCurrentLoginUser = oSWbemObject.UserName  
        Err.Clear  
    Next  
      
    If Cstr(sCurrentLoginUser) ="" Then  
        GetCurrentLoginUser = " "  
    Else  
        GetCurrentLoginUser = sCurrentLoginUser  
    End If  
      
    Set oSWbemServices = Nothing  
    Set oSWbemLocator = Nothing  
      
End Function