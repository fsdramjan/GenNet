class MyDeviceModel {
  var deviceName;
  var model;
  var manufacturer;
  var deviceType;
  var firmwareVersion;
  var uptime;
  var ipAddress;
  var gateway;
  var dnsServer;
  var signal;

  MyDeviceModel({
    this.deviceName,
    this.model,
    this.manufacturer,
    this.deviceType,
    this.firmwareVersion,
    this.uptime,
    this.ipAddress,
    this.gateway,
    this.dnsServer,
    this.signal,
  });
}
