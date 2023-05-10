//Monitor for unknown MAC addresses
// This active monitor watches MAC addresses present on a network by polling an SNMP-managed switch and the bridge MIB. 
// In the example script, you define a list of MAC addresses you will allow to connect to the network. This monitor will 
// fail if it finds devices that do not match the addresses specified in the list.

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

// Modify the list below. It defines a list of allowed mac addresses with mapping to switch interface   
// on the network.  
// This script will poll a managed switch using SNMP and the bridge MIB to detect MAC addresses present  
// on your network that should not be and to detect misplaced machines (connected to the wrong port).  
//  
// The MAC addresses should be typed lowercase with no padding using ':' between each bytes  
// for instance "0:1:32:4c:ef:9" and not "00:01:32:4C:EF:09"  
//  
var arrAllowedMacToPortMapping =  new ActiveXObject("Scripting.Dictionary");  
arrAllowedMacToPortMapping.add("0:3:ff:3b:df:1f", 17);  
arrAllowedMacToPortMapping.add("0:3:ff:72:5c:bf", 77);  
arrAllowedMacToPortMapping.add("0:3:ff:e2:e5:76", 73);  
arrAllowedMacToPortMapping.add("0:11:24:8e:e0:a5", 63);  
arrAllowedMacToPortMapping.add("0:1c:23:ae:b0:4c", 48);  
arrAllowedMacToPortMapping.add("0:1d:60:96:e5:58", 73);  
arrAllowedMacToPortMapping.add("0:e0:db:8:aa:a3", 73);  
  
var ERR_NOERROR = 0;  
var ERR_NOTALLOWED = 1;  
var ERR_MISPLACED = 2;  
function CheckMacAddress(sMacAddress, nPort)  
{  
    sMacAddress = sMacAddress.toLowerCase();  
      
    if (!arrAllowedMacToPortMapping.Exists(sMacAddress))  
    {  
        return ERR_NOTALLOWED;  
    }     
  
    var nAllowedPort = arrAllowedMacToPortMapping.Item(sMacAddress);  
    if (nAllowedPort != nPort)  
    {  
        return ERR_MISPLACED;  
    }  
    return ERR_NOERROR;  
}  
  
var oSnmpRqst = new ActiveXObject("CoreAsp.SnmpRqst");  
  
var oComResult = oSnmpRqst.Initialize(Context.GetProperty("DeviceID"));  
  
if (oComResult.Failed)  
{  
    Context.SetResult(1, oComResult.GetErrorMsg);  
}  
else  
{  
    var DOT1DTOFDBPORT_OID = "1.3.6.1.2.1.17.4.3.1.2";  
    var DOT1DTOFDBADDRESS_OID = "1.3.6.1.2.1.17.4.3.1.1";  
    var sOid = DOT1DTOFDBPORT_OID  
    var bStatus = true;  
    var arrMisplacedAddresses = new Array();  
    var arrNotAllowedAddresses = new Array();  
    var i=0;  
    while (i++<1000)  
    {  
        oComResult = oSnmpRqst.GetNext(sOid);  
        if (oComResult.Failed)  
        {  
            break;  
        }  
        sOid = oComResult.GetOID;  
        if (sOid.indexOf(DOT1DTOFDBPORT_OID) == -1)  
        {  
            // we are done walking  
            break;  
        }  
        var nPort = oComResult.GetPayload;  
  
        // the last 6 elements of the OID are the MAC address in OId format  
        var sInstance = sOid.substr(DOT1DTOFDBPORT_OID.length+1, sOid.length);  
  
        // get it in hex format...  
        oComResult = oSnmpRqst.Get(DOT1DTOFDBADDRESS_OID + "." + sInstance);  
        if (oComResult.Failed)  
        {  
            continue;  
        }  
        var sMAC = oComResult.GetValue;   
  
        var nError = CheckMacAddress(sMAC, nPort);  
  
        switch (nError)  
        {  
        case ERR_NOTALLOWED:  
            arrNotAllowedAddresses.push(sMAC + "(" + nPort + ")");  
            break;  
        case ERR_MISPLACED:  
            arrMisplacedAddresses.push(sMAC + "(" + nPort + ")");  
            break;  
        case ERR_NOERROR:  
        default:  
            // no problem         
        }  
    }  
  
    //Write the status  
    Context.LogMessage("Found " + i + " MAC addresses on your network.");  
    if (arrMisplacedAddresses.length > 0)  
    {  
        Context.LogMessage("Warning: Found " + arrMisplacedAddresses.length + " misplaced addresses: " + arrMisplacedAddresses.toString());  
    }  
    if (arrNotAllowedAddresses.length > 0)  
    {  
        Context.SetResult(1, "ERROR: Found " + arrNotAllowedAddresses.length + " unknown MAC addresses on your network: " + arrNotAllowedAddresses.toString());  
    }  
    else  
    {  
        Context.SetResult(0, "SUCCESS. No anomaly detected on the network");  
    }  
}