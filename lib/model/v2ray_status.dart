class V2RayStatus {
  final String duration;
  final String uploadSpeed;
  final String downloadSpeed;
  final String upload;
  final String download;
  final String state;

  V2RayStatus({
    this.duration = "00:00:00",
    this.uploadSpeed = "0.0 B/s",
    this.downloadSpeed = "0.0 B/s",
    this.upload = "0.0 B",
    this.download = "0.0 B",
    this.state = "DISCONNECTED",
  });
}
