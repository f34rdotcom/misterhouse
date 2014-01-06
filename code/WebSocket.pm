=begin comment
************************************************************************************

File:
        mh/lib/WebSocket.pm

Version: 
       1.0

Changes:
       2014-01-05: initial release weekend project

Description: 
        WebSocket is a next-generation bidirectional low latency communication 
      technology for web applications which operates over a single socket and is 
      exposed via a JavaScript interface in HTML 5 compliant browsers.

        This module provides a WebSocket server that integrates into MisterHouse.
      I have implemented a more async event based interface to the connected
      WebSocket clients. To access any message from the HTML 5 browser it is only
      necessary to subscribe with a callback function to that message type and the
      function will be called when the message arrives. 

        The latency from browser click to MH code execution or MH code sending and
      browser javascript function call should be less than 100ms. All lower level
      code uses pools and kernel level event driven sockets so minimal load is added
      to MH to run this module.

        Sending large 10K JSON informational messages to the HTML 5 based frontend 
      every 5 seconds would have minimal load on even wan based applications.

        As with all MisterHouse operations the callbacks must not block or consume
      too many cpu cycles. 
      

Author:
        Sean Mathews
        coder@f34r.com

License: 
      The MIT License (MIT)

      Copyright (c) 2014 Nu Tech Software Solutions, Inc.

      Permission is hereby granted, free of charge, to any person obtaining a copy
      of this software and associated documentation files (the "Software"), to deal
      in the Software without restriction, including without limitation the rights
      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      copies of the Software, and to permit persons to whom the Software is
      furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in
      all copies or substantial portions of the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
      THE SOFTWARE.


Install: 
        On raspbian I had a nightmare getting cpan to work. It must be
      a debian thing but I needed stuff not available via apt-get. I will
      try and better document this later but I will have to flatten my Pi
      a few times to do it right.

      cpan[1]> install Future
      cpan[1]> install Test
      cpan[1]> install IO::Async
      cpan[1]> install IO::Socket
      cpan[1]> install Protocol::WebSocket

Usage:
        Just place it in your user code directory (code_dir in your config file).
      You must then add the following configuration items to your mh.ini

      websocket_module=WebSocket
      websocket_port=3000
      websocket_bind_ip=0.0.0.0


      # in your private code subscribe to be called on events
      # your function will have one argument the JSON message
      # from the WebSocket client
      WebSocket::subscribe('some_action', \&MyFunction);
      
      # send a command to all connected websockets 
      WebSocket::SendToAll("some_command");

Example:
      mh/lib/WebSocketTest.pl
      mh/web/my_mh/websockettest.html

Todo:
      more error checking
      missing functions
      improve example 
      comments and cleanup
      feature addressing pub/sub

************************************************************************************
=cut

use strict;

package WebSocket;

use IO::Socket::INET;
use IO::Async::Listener;
use IO::Async::Loop;
use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;

# globals
my $websocket_loop = undef;       # the Async::Loop
my $websocket_listener = undef;   # the Async::Listener
my %commandfunc = undef;          # the dispatch table

# add a listener for a given websocket command
sub subscribe {
  my ($command, $function) = @_; 
  $commandfunc{$command} = $function;
}

# remove a listenr for a given websocket command
sub unsubscribe {
  #todo
}

# called by mh if configured in mh.ini
sub startup {

    # define our loop callback
    &::MainLoop_pre_add_hook(  \&WebSocket::Loop, 1 );

    # construct our Async::Loop 
    $websocket_loop = IO::Async::Loop->new;

    # construct our listener socket
    $websocket_listener = IO::Async::Listener->new(
       on_stream => sub {
          my ($self, $stream) = @_;

          my $hs    = Protocol::WebSocket::Handshake::Server->new;
          my $frame = Protocol::WebSocket::Frame->new;

          $stream->configure(
              on_read => sub {
                  my ($self, $buffref, $closed) = @_;

                  # check if we are authenticating
                  if (!$hs->is_done) {
                      $hs->parse($$buffref);
                      if ($hs->is_done) {
                          $self->write($hs->to_string);
                      }

                      $$buffref = "";
                      return 0;
                  }

                  # add the frame(s) we just received
                  $frame->append($$buffref);

                  # process every frame
                  while (my $message = $frame->next) {

                      # attempt to conver the JSON message to a perl object
                      my $json;
                      eval { $json = JSON::decode_json($message) } || do {
                         &::print_log("received malformed json message '$message'");
                         return 0;
                      };

                      my $found = 0;
                      my $type =  $json->{'type'};
                      
                      # some logging needs verbosity setting
                      &::print_log( "received json message type [" . $type ."]" );

                      # call any dispatch functions who want this command
                      # in effect a multicast delegate
                      foreach my $k (keys %commandfunc) {
                         if( $type eq $k ) {
                            # needs verbosity setting
                            &::print_log("found dispatch calling it");
                            my $result = $commandfunc{$k}->( \$json );
                            $found ++;
                         }
                      }
                     
                      # report an event fired into the ground 
                      if(!$found) {
                         &::print_log( "no dispatcher found for event" ) 
                      } 
                  }

                  $$buffref = "";
                  return 0;
              }
          );

          # add our client socket to our Async::Loop
          &::print_log("new websocket connection established");
          $websocket_loop->add($stream);
      }
    );

    # add our listener to the Async::Loop
    $websocket_loop->add( $websocket_listener );

    my $socket_port =  $::config_parms{websocket_port};
    my $socket_bind_ip = $::config_parms{websocket_bind_ip};

    my $socket = IO::Socket::INET->new(
       LocalAddr => $socket_bind_ip,
       LocalPort => $socket_port,
       Listen    => 1,
       ReuseAddr => 1,
    );

    # add the Listen socket to our listener
    $websocket_listener->listen(handle => $socket);
}


# send a message to all connected websockets
sub SendToAll {
     my ($self, $message) = @_;

     my @notifiers = $websocket_loop->notifiers;
     my $count = 0;
     foreach my $notify (@notifiers) {
       if (ref($notify) eq "IO::Async::Stream") {
         my $sframe = Protocol::WebSocket::Frame->new;
         $notify->write($sframe->new("UPDATE")->to_bytes);
         $count++;
       }
     }
}

# loop callback called by MisterHouse every cycle
sub Loop {
    # we could improve latency here if we had a predictive loop time
    # for now do the least 0

    # Just give our event loop some cpu cycles.
    my $result = $websocket_loop->loop_once(0);
}

1;

