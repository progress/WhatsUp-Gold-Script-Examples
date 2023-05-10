//Monitoring printer ink level and utilization

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

//Note: This jscript is only a code example. The Printer Active Monitor should be used to monitor printers.

var nMarkerPercentUtilization = 70; // This monitor will fail if the printer ink utilization is above this value %. 
var oSnmpRqst = new ActiveXObject("CoreAsp.SnmpRqst"); //Create the object for the SNMP request
var nDeviceID = Context.GetProperty("DeviceID"); //Use Context.GetProperty to get the DeviceID from WhatsUp Gold
var oComResult = oSnmpRqst.Initialize(nDeviceID); //Open the SNMP connection using the deviceID
if (oComResult.Failed) {  
    Context.SetResult(1, oComResult.GetErrorMsg);  //If we can't connect, set the result to down with the error message as a status
}  
else {  
    // poll the two counters  
    Context.LogMessage("Polling marker maximum level");
    var oResponse = oSnmpRqst.Get("1.3.6.1.2.1.43.11.1.1.8.1.1");  
    if (oResponse.Failed) {  
        Context.SetResult(1, oResponse.GetErrorMsg);  
    }  
    var prtMarkerSuppliesMaxCapacity = oResponse.GetValue;  
    Context.LogMessage("Success. Value=" + prtMarkerSuppliesMaxCapacity);  
  
    Context.LogMessage("Polling marker current level");  
    oResponse = oSnmpRqst.Get("1.3.6.1.2.1.43.11.1.1.9.1.1");  
    if (oResponse.Failed) {  
        Context.SetResult(1, oResponse.GetErrorMsg);  
    }  
    var prtMarkerSuppliesLevel = oResponse.GetValue;  
    Context.LogMessage("Success. Value=" + prtMarkerSuppliesLevel);  
  
    var nPercentUtilization = 100 * prtMarkerSuppliesLevel / prtMarkerSuppliesMaxCapacity;  
  
    if (nPercentUtilization > nMarkerPercentUtilization) {  
        Context.SetResult(1, "Failure. Current Utilization (" + (nPercentUtilization + "%) is above the configured threshold (" + nMarkerPercentUtilization) + "%)");  
    }  
    else {  
        Context.SetResult(0, "Success. Current Utilization (" + (nPercentUtilization + "%) is below the configured threshold (" + nMarkerPercentUtilization) + "%)");  
    }  
}  