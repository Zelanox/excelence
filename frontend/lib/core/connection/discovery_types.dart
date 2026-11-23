/// One datagram received while looking for the server.
class UdpReply {
  const UdpReply(this.data, this.host);

  final List<int> data;

  /// The IPv4 address the datagram came from.
  final String host;
}
