# Category=touchScreen
#@ HTML 5 Touchscreen interface backend using WebSockets
#
#    Sean Mathews
#       coder at f34r dot com
#
############################################################################

#noloop=start

# map click messages to functions
my %clicks = (
  "power_button"  => sub {
    my ( $json ) = @_;
    &::print_log("power_button clicked '$$json'");
    set $v_reload_code ON;
  },
  "some_button"  => sub {
    my ( $json ) = @_;
    &::print_log("some_button clicked");
  },
);

# dispatch routine for "click" command sent a reference to the json object
sub TouchClick {
  # the full json object sent from the browser
  my ( $json ) = @_;

  &::print_log("TouchClick called with '$$json'");

  # get the click argument and use it to find a handler function
  my $click_id =  $$json->{'text'};
  if ($clicks{$click_id}) {
      $clicks{$click_id}->($json);
  } else {
      &::print_log("no such click handler: $click_id");
  }
}

# subscribe to click event messages
WebSocket::subscribe('click', \&TouchClick);

#noloop=stop

# This is run on startup or reload. Tell everyone what happend.
if ($Startup or $Reload) {
  &::print_log("notify all WebSockets we restarted");
  WebSocket::SendToAll("RESTART");
}
