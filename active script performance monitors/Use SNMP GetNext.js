//Use SNMP GetNext
// This performance monitor walks the hrStorageType MIB to find hard disks in the storage table. 
// After a hard disk is found, it obtains indexes of it and polls new objects (the storage size and units).

// Note: This example is provided as an illustration only and is not supported.
// Technical support is available for the Context object, SNMP API, and scripting environment, 
// but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
// For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
// or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

// This scripts walks hrStorageType to find hard disks in the storage table.  
// A hard disk as a hrStorageType of "1.3.6.1.2.1.25.2.1.4" (hrStorageFixedDisk).  
// Then it gets the indexes of the hard disk in that table and for each index, it polls two new  
// objects in that table, the storage size and the units of that entry.  
// It adds everything up and converts it in Gigabytes.  
var hrStorageType = "1.3.6.1.2.1.25.2.3.1.2";  
  
// Create and initialize the snmp object  
var oSnmpRqst = new ActiveXObject("CoreAsp.SnmpRqst");  
var nDeviceID = Context.GetProperty("DeviceID");  
var oResult = oSnmpRqst.Initialize(nDeviceID);  
  
var arrIndexes = new Array(); // array containing the indexes of the disks we found  
// walk the column in the table:  
var oSnmpResponse = oSnmpRqst.GetNext(hrStorageType);  
if (oSnmpResponse.Failed) Context.SetResult(1, oSnmpResponse.GetPayload);  
var sOid = String(oSnmpResponse.GetOid);  
var sPayload = String(oSnmpResponse.GetPayload);  
  
while (!oSnmpResponse.Failed && sOid < (hrStorageType + ".99999999999"))  
{  
    if (sPayload == "1.3.6.1.2.1.25.2.1.4") {  
        // This storage entry is a disk, add the index to the table.  
        // the index is the last element of the OID:  
        var arrOid = sOid.split(".");  
        arrIndexes.push(arrOid[arrOid.length - 1]);  
    }  
  
    oSnmpResponse = oSnmpRqst.GetNext(sOid);  
    if (oSnmpResponse.Failed) Context.SetResult(1, oSnmpResponse.GetPayload);  
    sOid = String(oSnmpResponse.GetOid);  
    sPayload = String(oSnmpResponse.GetPayload);  
}  
Context.LogMessage("Found disk indexes: " + arrIndexes.toString());  
if (arrIndexes.length == 0) Context.SetResult(1, "No disk found");  
  
// now that we have the indexes of the disks. Poll their utilization and units  
var nTotalDiskSize = 0;  
for (var i = 0; i < arrIndexes.length; i++) {  
  
    oSnmpResponse = oSnmpRqst.Get("1.3.6.1.2.1.25.2.3.1.5." + arrIndexes[i])  
    if (oSnmpResponse.Failed) Context.SetResult(1, oSnmpResponse.GetPayload);  
    nSize = oSnmpResponse.GetPayload;  
    oSnmpResponse = oSnmpRqst.Get("1.3.6.1.2.1.25.2.3.1.4." + arrIndexes[i])  
    if (oSnmpResponse.Failed) Context.SetResult(1, oSnmpResponse.GetPayload);  
    nUnits = oSnmpResponse.GetPayload;  
  
    nTotalDiskSize += (nSize * nUnits);  
}  
// return the total size in gigabytes.  
Context.SetValue(nTotalDiskSize / 1024 / 1024 / 1024); // output in Gigabytes  