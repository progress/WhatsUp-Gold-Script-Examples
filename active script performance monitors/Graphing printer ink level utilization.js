//Graphing printer ink level utilization
// This performance monitor uses two reference variables to poll and 
// compute the ink level percent utilization of a printer for later graphing.

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

// prtMarkerSuppliesLevel is an snmp reference variable defined with an OID or 1.3.6.1.2.1.43.11.1.9 and an instance of 1.1  
// prtMarkerSuppliesMaxCapacity is an snmp reference variable defined with an OID or 1.3.6.1.2.1.43.11.1.8 and an instance of 1.1  
Context.LogMessage("Print the current marker level");  
var prtMarkerSuppliesLevel = Context.GetReferenceVariable("prtMarkerSuppliesLevel");  
Context.LogMessage("Print the maximum marker level");  
var prtMarkerSuppliesMaxCapacity = Context.GetReferenceVariable("prtMarkerSuppliesMaxCapacity");  
  
if (prtMarkerSuppliesMaxCapacity == null || prtMarkerSuppliesLevel == null) {  
    Context.SetResult(0, "Failed to poll printer ink levels.");  
}  
else {  
    Context.LogMessage("marker lever successfully retrieved");  
    var nPercentMarkerUtilization = 100 * prtMarkerSuppliesLevel / prtMarkerSuppliesMaxCapacity;  
    Context.LogMessage("Percent utilization=" + nPercentMarkerUtilization + "%");  
    Context.SetValue(nPercentMarkerUtilization);
}