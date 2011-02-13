use strict;
use warnings;

package Gentoo::ChangeLog::Parser::Eventual;

# ABSTRACT: Event-Based ChangeLog format parser, inspired by Pod::Eventual.

{
  use Moose;

  has context => ( isa => 'Str', is => 'rw', default => 'pre-parse' );

  has event_register => ( isa => 'ArrayRef[ CodeRef ]', is => 'rw', lazy_build => 1 );

  has callback => (
    isa        => 'CodeRef',
    is         => 'rw',
    lazy_build => 1,
    traits     => ['Code'],
    'handles'  => { handle_event => 'execute_method', }
  );

  sub _event_data {
    my ( $self, %other ) = @_;
    return { content => $self->{WORKLINE}, %other, %{ $self->{PASSTHROUGH} } };
  }

  sub handle_line {
    my ( $self, $line, $passthrough ) = @_;

    $passthrough ||= {};

    local $self->{WORKLINE}    = $line;
    local $self->{PASSTHROUGH} = $passthrough;

  RULE: for my $event ( @{ $self->event_register } ) {
      local $_ = $self;

      my $result = $event->( $self, $line );

      next RULE if $result eq 'next';
      return    if $result eq 'fail';
      return 1  if $result eq 'return';
      die "Bad return $result\n";
    }
  }

  sub _build_event_register {
    return [
      \&_event_start,               \&_event_blank,                  \&_event_header_comment,
      \&_event_header_end,          \&_event_release_line,           \&_event_change_header,
      \&_event_begin_change_header, \&_event_continue_change_header, \&_event_end_change_header,
      \&_event_change_body,         \&_event_unknown
    ];
  }

  sub _build_callback {
    die "Not implementeted!";
  }

  sub _event_start {
    return 'next' if $_->context ne 'pre-parse';
    $_->handle_event( 'start' => $_->_event_data() );
    $_->context('document');
    return 'next';
  }

  sub _event_blank {
    return 'next' if $_->{WORKLINE} !~ /^\s*$/;
    $_->handle_event( 'blank' => $_->_event_data() );
    return 'return';
  }

  sub _event_header_comment {
    return 'next' if $_->{WORKLINE} !~ /^#\s*/;
    if ( $_->context eq 'document' ) {
      $_->handle_event( 'header' => $_->_event_data() );
      $_->context('header');
    }
    $_->handle_event( 'header_comment' => $_->_event_data() );
    return 'return';
  }

  sub _event_header_end {
    return 'next'
      if ( $_->context() ne 'pre-parse' )
      and ( $_->context() ne 'header' );

    $_->handle_event( 'header_end' => $_->_event_data() );
    $_->context('body');
    return 'next';
  }

  sub _event_release_line {
    return 'next'
      if ( $_->context() ne 'body' )
      and ( $_->context() ne 'changebody' );
    return 'next' if $_->{WORKLINE} !~ /^\*/;
    if ( $_->context eq 'changebody' ) {
      $_->handle_event( 'end_change_body' => $_->_event_data() );
    }

    $_->handle_event( 'release_line' => $_->_event_data() );
    return 'return';
  }

  sub _event_change_header {
    return 'next' if ( $_->context() ne 'body' ) and ( $_->context() ne 'changebody' );
    return 'next' if ( $_->{WORKLINE} !~ /^[ ]{2}\d\d?[ ][A-Z][a-z]+[ ]\d\d+;.*:\s*$/ );
    if ( $_->context eq 'changebody' ) {
      $_->handle_event( 'end_change_body' => $_->_event_data() );
    }
    $_->handle_event( 'change_header' => $_->_event_data() );
    $_->context('changebody');
    return 'return';
  }

  sub _event_begin_change_header {
    return 'next'
      unless ( $_->context() eq 'body' )
      or ( $_->context() eq 'changebody' );
    return 'next' if ( $_->{WORKLINE} !~ /^[ ]{2}\d\d?[ ][A-Z][a-z]+[ ]\d\d+;.*$/ );
    $_->handle_event( 'begin_change_header' => $_->_event_data() );
    $_->context("changeheader");
    return 'return';
  }

  sub _event_continue_change_header {
    return 'next' unless $_->context eq 'changeheader';
    return 'next' if $_->{WORKLINE} =~ /:\s*$/;
    $_->handle_event( 'continue_change_header' => $_->_event_data() );
    return 'return';
  }

  sub _event_end_change_header {
    return 'next' unless $_->context eq 'changeheader';
    return 'next' unless $_->{WORKLINE} =~ /:\s*$/;
    $_->handle_event( 'end_change_header' => $_->_event_data() );
    $_->context('changebody');
    return 'return';
  }

  sub _event_change_body {
    return 'next' unless $_->context eq 'changebody';
    return 'next' unless $_->{WORKLINE} =~ /^[ ]{2}/;
    $_->handle_event( 'change_body' => $_->_event_data() );
    return 'return';
  }

  sub _event_unknown {
    $_->handle_event( 'UNKNOWN' => $_->_event_data() );
    return 'return';
  }
  __PACKAGE__->meta->make_immutable;

}

1;
