#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2012 -- leonerd@leonerd.org.uk

package IO::Async::Loop::Mojo;

use strict;
use warnings;

our $VERSION = '0.01';
use constant API_VERSION => '0.33';

use base qw( IO::Async::Loop );
IO::Async::Loop->VERSION( '0.33' );

use Carp;

use Mojo::IOWatcher;

=head1 NAME

C<IO::Async::Loop::Mojo> - use C<IO::Async> with C<Mojolicious>

=head1 SYNOPSIS

 use IO::Async::Loop::Mojo;

 my $loop = IO::Async::Loop::Mojo->new();

 $loop->add( ... );

 ...
 # Rest of Mojolicious code here

=head1 DESCRIPTION

This subclass of L<IO::Async::Loop> uses L<Mojo::IOWatcher> to perform its IO
operations. It allows the use of L<IO::Async>-based code or modules from
within a L<Mojolicious> application.

=head1 CONSTRUCTOR

=cut

=head2 $loop = IO::Async::Loop::Mojo->new()

This function returns a new instance of a C<IO::Async::Loop::Mojo> object. It
takes no special arguments.

=cut

sub new
{
   my $class = shift;
   my $self = $class->__new( @_ );

   $self->{watcher} = Mojo::IOWatcher->new;

   return $self;
}

=head1 METHODS

There are no special methods in this subclass, other than those provided by
the C<IO::Async::Loop> base class.

=cut

sub watch_io
{
   my $self = shift;
   my %params = @_;

   my $handle = $params{handle} or croak "Expected 'handle'";
   my $fd = $handle->fileno;

   my $watcher = $self->{watcher};

   my $cbs;
   $cbs = $self->{io_cbs}{$fd} ||= do {
      # Install the watch function
      $watcher->io( $handle => sub {
         my ( $watcher, undef, $writable ) = @_;
         if( $writable ) {
            $cbs->[1]->();
         }
         else {
            $cbs->[0]->();
         }
         $watcher->stop;
      } );

      [];
   };

   if( my $on_read_ready = $params{on_read_ready} ) {
      $cbs->[0] = $on_read_ready;
   }

   if( my $on_write_ready = $params{on_write_ready} ) {
      $cbs->[1] = $on_write_ready;
   }

   $watcher->watch( $handle => defined $cbs->[0], defined $cbs->[1] );
}

sub unwatch_io
{
   my $self = shift;
   my %params = @_;

   my $handle = $params{handle} or croak "Expected 'handle'";
   my $fd = $handle->fileno;

   my $watcher = $self->{watcher};

   my $cbs = $self->{io_cbs}{$fd} or return;

   if( $params{on_read_ready} ) {
      undef $cbs->[0];
   }

   if( $params{on_write_ready} ) {
      undef $cbs->[1];
   }

   if( defined $cbs->[0] or defined $cbs->[1] ) {
      $watcher->watch( $handle => defined $cbs->[0], defined $cbs->[1] );
   }
   else {
      $watcher->drop( $handle );
      delete $self->{io_cbs}{$fd};
   }
}

sub enqueue_timer
{
   my $self = shift;
   my ( %params ) = @_;

   my $watcher = $self->{watcher};

   my $delay;
   if( exists $params{time} ) {
      my $now = exists $params{now} ? $params{now} : $self->time;

      $delay = delete($params{time}) - $now;
   }
   elsif( exists $params{delay} ) {
      $delay = delete $params{delay};
   }
   else {
      croak "Expected either 'time' or 'delay' keys";
   }

   my $code = delete $params{code};

   my $callbacks = $self->{timercallbacks};

   my $id;
   my $callback = sub {
      my $watcher = shift;
      $code->();
      delete $callbacks->{$id};
      $watcher->stop;
   };

   $id = $watcher->timer( $delay => $callback );

   $callbacks->{$id} = $code;

   return $id;
}

sub cancel_timer
{
   my $self = shift;
   my ( $id ) = @_;

   my $watcher = $self->{watcher};

   $watcher->drop( $id );
   delete $self->{timercallbacks}{$id};

   return;
}

sub requeue_timer
{
   my $self = shift;
   my ( $id, %params ) = @_;

   my $callback = $self->{timercallbacks}{$id};
   defined $callback or croak "No such enqueued timer";

   $self->cancel_timer( $id );

   return $self->enqueue_timer( %params, code => $callback );
}

sub loop_once
{
   my $self = shift;
   my ( $timeout ) = @_;
   my $watcher = $self->{watcher};

   $self->_adjust_timeout( \$timeout );

   my $timeout_id = $watcher->timer( $timeout => sub {
      my $watcher = shift;
      $watcher->stop;
   } );

   # Start the watcher; when something happens it will stop
   $watcher->start;

   $self->_manage_queues;

   $watcher->drop( $timeout_id );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
