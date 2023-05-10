//Monitor bandwidth utilization on an interface
// This active monitor is used to monitor the total bandwidth utilization (both in and out octets) 
// of an interface by polling values of the interface MIB.

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

// Settings for this monitor:  
// the interface index ifIndex:  
var nInterfaceIndex = 65540;  
  
// this monitor will fail if the interface utilization goes above this current ratio:  
// current bandwidth / maxBandwidth > nMaxInterfaceUtilizationRatio   
var nMaxInterfaceUtilizationRatio = 0.7; // Set to 70%  
  
// Create an SNMP object, that will poll the device.  
var oSnmpRqst = new ActiveXObject("CoreAsp.SnmpRqst");  
  
// Get the device ID  
var nDeviceID = Context.GetProperty("DeviceID");  
  
// This function polls the device returns the ifSpeed of the inteface indexed by nIfIndex.  
// ifSpeed is in bits per second.  
function getIfSpeed(nIfIndex) {  
    var oResult = oSnmpRqst.Initialize(nDeviceID);  
    if (oResult.Failed) {  
        return null;  
    }  
    return parseInt(SnmpGet("1.3.6.1.2.1.2.2.1.5." + nIfIndex)); // ifSpeed  
}  
// Function to get SNMP ifInOctets for the interface indexed by nIfIndex (in bytes).  
// Returns the value polled upon success, null in case of failure.  
function getInOctets(nIfIndex) {  
    var oResult = oSnmpRqst.Initialize(nDeviceID);  
    if (oResult.Failed) {  
        return null;  
    }  
    return parseInt(SnmpGet("1.3.6.1.2.1.2.2.1.10." + nIfIndex)); // inOctets  
}  
  
// Function to get SNMP ifOutOctets for the interface indexed by nIfIndex (in bytes).  
// Returns the value polled upon success, null in case of failure.  
function getOutOctets(nIfIndex) {  
    var oResult = oSnmpRqst.Initialize(nDeviceID);  
    if (oResult.Failed) {  
        return null;  
    }  
    return parseInt(SnmpGet("1.3.6.1.2.1.2.2.1.16." + nIfIndex)); //  outOctets  
}  
  
// Helper function to get a specific SNMP object (OID in sOid).  
// Returns the value polled upon success, null in case of failure.  
function SnmpGet(sOid) {  
    var oResult = oSnmpRqst.Get(sOid);  
    if (oResult.Failed) {  
        return null;  
    }  
    else {  
        return oResult.GetPayload;  
    }  
}  
  
// Get the current date. It will be used as a reference date for the SNMP polls.  
var oDate = new Date();  
var nPollDate = parseInt(oDate.getTime()); // get the date in millisec in an integer.  
// Do the actual polling:  
var nInOctets = getInOctets(nInterfaceIndex);  
var nOutOctets = getOutOctets(nInterfaceIndex);  
var nIfSpeed = getIfSpeed(nInterfaceIndex);  
if (nInOctets == null || nOutOctets == null || nIfSpeed == null) {  
    Context.SetResult(1, "Failure to poll this device.");  
}  
else {  
    var nTotalOctets = nInOctets + nOutOctets;  
    // Retrieve the octets value and date of the last poll saved in a context variable:  
    var nInOutOctetsMonitorPreviousPolledValue = Context.GetProperty("nInOutOctetsMonitorPreviousPolledValue");  
    var nInOutOctetsMonitorPreviousPollDate = Context.GetProperty("nInOutOctetsMonitorPreviousPollDate");  
    if (nInOutOctetsMonitorPreviousPolledValue == null || nInOutOctetsMonitorPreviousPollDate == null) {  
        // the context variable has never been set, this is the first time we are polling.  
        Context.LogMessage("This monitor requires two polls.");  
        Context.SetResult(0, "success");  
    }  
    else {  
        // compute the bandwidth that was used between this poll and the previous poll  
        var nIntervalSec = (nPollDate - nInOutOctetsMonitorPreviousPollDate) / 1000; // time since  last poll in seconds  
        var nCurrentBps = (nTotalOctets - nInOutOctetsMonitorPreviousPolledValue) * 8 / nIntervalSec;  
        Context.LogMessage("total octets for interface " + nInterfaceIndex + " = " + nTotalOctets);  
        Context.LogMessage("previous value = " + nInOutOctetsMonitorPreviousPolledValue);  
        Context.LogMessage("difference: " + (nTotalOctets - nInOutOctetsMonitorPreviousPolledValue) + " bytes");  
        Context.LogMessage("Interface Speed: " + nIfSpeed + "bps");  
        Context.LogMessage("time elapsed since last poll: " + nIntervalSec + "s");  
        Context.LogMessage("Current Bandwidth utilization: " + nCurrentBps + "bps");  
        if (nCurrentBps / nIfSpeed > nMaxInterfaceUtilizationRatio) {  
            Context.SetResult(1, "Failure: bandwidth used on this interface " + nCurrentBps + "bps / total available: " + nIfSpeed + "bps is above the specified ratio: " + nMaxInterfaceUtilizationRatio);  
        }  
        else {  
            Context.SetResult(0, "Success");  
        }  
    }  
    // Save this poll information in the context variables:  
    Context.PutProperty("nInOutOctetsMonitorPreviousPolledValue", nTotalOctets);  
    Context.PutProperty("nInOutOctetsMonitorPreviousPollDate", nPollDate);  
}  