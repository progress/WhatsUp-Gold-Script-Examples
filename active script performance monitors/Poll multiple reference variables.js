//Poll multiple reference variables
// This performance monitor graphs the percentage of retransmitted TCP segments over time using two reference variables: RVtcpOytSegs and RVtcpRetransSegs.

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

// This script is a JScript that will allow you to graph the percentage of restransmitted TCP   
//' segments over time on a device.  
// For this script, we use two SNMP reference variables:  
//' The first Reference variable RVtcpOutSegs is defined with OID 1.3.6.1.2.1.6.11 and instance 0. It polls the  
//' SNMP object tcpOutSegs.0, the total number of tcp segments sent out on the network.  
var RVtcpOutSegs = parseInt(Context.GetReferenceVariable("RVtcpOutSegs"));  
  
// The second reference variable RVtcpRetransSegs is defined with OID 1.3.6.1.2.1.6.12 and instance 0. It polls  
// the SNMP object tcpRetransSegs.0, the total number of TCP segments that were retransmitted on the system.  
var RVtcpRetransSegs = parseInt(Context.GetReferenceVariable("RVtcpRetransSegs"));  
  
if (isNaN(RVtcpRetransSegs) || isNaN(RVtcpOutSegs)) {  
    Context.SetResult(1, "Failed to poll the reference variables.");  
}  
else {  
    // Compute the percentage:  
    var TCPRetransmittedPercent = 100 * RVtcpRetransSegs / RVtcpOutSegs;  
    // Set the performance monitor value to graph  
    Context.SetValue(TCPRetransmittedPercent);  
} 