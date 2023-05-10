//Poll a reference variable and perform a calculation
// This performance monitor polls a reference variable, and then 
// performs an arithmetic calculation with the returned value.

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

// This script is a JScript that demonstrates how to use a reference variable in a script.  
// The reference variable "RVsysUpTime" is an SNMP reference variable defined  
// with an OID of 1.3.6.1.2.1.1.3 and instance of 0.  
  
// Poll reference variable RVsysUpTime  
var RVsysUpTime = Context.GetReferenceVariable("RVsysUpTime");  
  
if (RVsysUpTime == null) {  
    // Pass a non zero error code upon failure with an error message.  
    // The error message will be logged in the Performance Monitor Error Log  
    // and in the eventviewer.  
    Context.SetResult(1, "Failed to poll the reference variable.");  
}  
else {  
    // Success, use the polled value to convert sysUpTime in hours.  
    // sysUpTime is an SNMP timestamp which is in hundredths of seconds:  
    var sysUpTimeHours = RVsysUpTime / 3600 / 100;  
    // Save the final value to graph:  
    Context.SetValue(sysUpTimeHours);  
}  