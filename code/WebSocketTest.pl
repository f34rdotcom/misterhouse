# Category=Test
#@ testing WebSocket interface
#
# ###########################################################################


#noloop=start

# dispatch routine for "click" command
sub MyFunction {
  my ( $json ) = @_;
  &::print_log("MyFunction called with '$$json'");
}

WebSocket::subscribe('click', \&MyFunction);

#noloop=stop
