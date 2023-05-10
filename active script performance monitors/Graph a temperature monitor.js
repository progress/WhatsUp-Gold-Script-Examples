//Graph a temperature monitor
//This performance monitor polls an SNMP-enabled temperature sensor using the CurTemp reference variable.

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration


// This script is a JScript script that polls the temperature of an snmp-enabled sensor from "uptime devices" (www.uptimedevices.com).  
// It uses an SNMP reference variable named CurTemp defined with an OID of 1.3.6.1.4.1.3854.1.2.2.1.16.1.14  
// and an instance of 1.  
//  
// That device indicates the temperature in degrees Fahrenheit.  
var oCurTemp = Context.GetReferenceVariable("CurTemp");  
if (oCurTemp == null) {  
    Context.SetResult(1, "Unable to poll Temperature Sensor");  
}  
else {  
    // convert temperature from tenth of degrees to degrees  
    var nFinalTemp = oCurTemp / 10.0;  
  
    // comment out the line below to convert the temperature in Celsius degrees:  
    //nFinalTemp = (nFinalTemp - 32) * 5 / 9;  
    Context.SetValue(nFinalTemp);  
} 