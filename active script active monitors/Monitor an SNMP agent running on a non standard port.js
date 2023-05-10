//Monitor an SNMP agent running on a non standard port
//This active monitor watches an SNMP agent running on a non-standard port (the standard SNMP port is 161).

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

var nSNMPPort = 1234; // change this value to the port your agent is running on  
var oSnmpRqst =  new ActiveXObject("CoreAsp.SnmpRqst");  
// Get the device ID  
var nDeviceID = Context.GetProperty("DeviceID");  
  
// Initialize the SNMP request object  
var oResult = oSnmpRqst.Initialize(nDeviceID);  
  
if(oResult.Failed)  
{  
Context.SetResult(1, oResult.GetPayload);  
}  
else  
{  
    // Set the request destination port.   
    var oResult = oSnmpRqst.SetPort(nSNMPPort);  
  
    // Get sysDescr.  
    var oResult = oSnmpRqst.Get("1.3.6.1.2.1.1.1.0");  
    if (oResult.Failed)  
    {  
        Context.SetResult(1, "Failed to poll device using port " + nSNMPPort + ". Error=" + oResult.GetPayload);  
    }  
    else  
    {  
        Context.SetResult(0, "SUCCESS. Detected an SNMP agent running on port " + nSNMPPort );  
    }  
}  