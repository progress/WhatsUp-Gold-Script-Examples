//Alert when temperature exceeds or drops out of range
// This jscript script polls the temperature from an snmp-enabled sensor from "uptime devices" (www.uptimedevices.com),  
// and makes sure the temperature is within an acceptable range configured right below.  
// The OID of the temperature object for that device is 1.3.6.1.4.1.3854.1.2.2.1.16.1.14.1 

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration
 
var nMinAllowedTemp = 65;  
var nMaxAllowedTemp = 75;  
var oSnmpRqst = new ActiveXObject("CoreAsp.SnmpRqst");  
var nDeviceID = Context.GetProperty("DeviceID");  
var oComResult = oSnmpRqst.Initialize(nDeviceID);  
if (oComResult.Failed) {  
    Context.SetResult(1, oComResult.GetErrorMsg);  
}  
else {  
    // poll the two counters  
    Context.LogMessage("Polling the temperature");  
    var oResponse = oSnmpRqst.Get("1.3.6.1.4.1.3854.1.2.2.1.16.1.14.1");  
    if (oResponse.Failed) {  
        Context.SetResult(1, oResponse.GetErrorMsg);  
    }  
    else {  
        var nTemperature = oResponse.GetValue / 10.0;  
        // comment out the following line to convert the temperature to Celcius degrees  
        //nTemperature = (nTemperature - 32) * 5 / 9;  
        Context.LogMessage("Success. Value=" + nTemperature + " degrees");  
  
        if (nTemperature < nMinAllowedTemp || nTemperature > nMaxAllowedTemp) {  
            Context.SetResult(1, "Polled temperature " + nTemperature + " is outside of the defined range " + nMinAllowedTemp + " - " + nMaxAllowedTemp);  
        }  
        else {  
            Context.SetResult(0, "Success");  
        }  
    }  
}  