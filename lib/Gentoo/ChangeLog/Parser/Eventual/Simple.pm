
use strict;
use warnings;

package Gentoo::ChangeLog::Parser::Eventual::Simple;

# ABSTRACT: A very crude Changelog -> Graph translation.
{
  use Carp qw( croak );
  use Moose;
  use namespace::clean -except => 'meta';

  has 'parser' => (
    isa     => 'Object',
    is      => 'rw',
    lazy    => 1,
    default => sub {
      my $self = shift;
      require Gentoo::ChangeLog::Parser::Eventual;
      Gentoo::ChangeLog::Parser::Eventual->new(
        callback => sub {
          $self->_callback->( $self, @_ );
        }
      );
    },
  );

  has '_callback' => (
    isa     => 'CodeRef',
    is      => 'rw',
    lazy    => 1,
    default => sub { croak('NOT REALLY AUTOMATIC, need to specify _callback') },
  );

  sub parse_lines {
    my ( $class, $lines ) = @_;

    my @output;
    my %stash;

    my $instance = $class->new(
      _callback => sub {
        my ( $self, $parser, $event, $opts ) = @_;

        # warn "\e[31m$event \e[32m" . $opts->{line} . " => \e[0m" . $opts->{content} . "\n";
        return if $event eq 'start';
        if ( $event eq 'header' ) {
          $stash{header} = [];
          return;
        }
        if ( $event eq 'header_comment' ) {
          push @{ $stash{header} }, $opts;
          return;
        }
        if ( $event eq 'header_end' ) {
          push @output, { 'header' => $stash{header}, line => $stash{header}->[0]->{line} };
          delete $stash{header};
          return;
        }
        if ( $event eq 'change_header' ) {
          $stash{changeheader} = [];
          push @{ $stash{changeheader} }, $opts;
          $stash{changebody} = [];
          return;
        }
        if ( $event eq 'begin_change_header' ) {
          $stash{changeheader} = [];
          push @{ $stash{changeheader} }, $opts;
          $stash{changebody} = [];
          return;
        }
        if ( $event eq 'continue_change_header' ) {
          push @{ $stash{changeheader} }, $opts;
          return;
        }
        if ( $event eq 'end_change_header' ) {
          push @{ $stash{changeheader} }, $opts;
          return;
        }
        if ( $event eq 'change_body' ) {
          push @{ $stash{changebody} }, $opts;
          return;
        }
        if ( $event eq 'end_change_body' ) {
          push @output, {
            change => {
              header => $stash{changeheader},
              body   => $stash{changebody},
            },
            line => $stash{changeheader}->[0]->{'line'},

          };
          delete $stash{changeheader};
          delete $stash{changebody};
          return;
        }
        if ( $event eq 'release_line' ) {
          push @output, { release => $opts, line => $opts->{line} };
          return;
        }
        if ( $event eq 'blank' ) {
          push @output, { 'blank' => $opts, line => $opts->{line} };
          return;
        }
        push @output, { UNHANDLED => { $event => $opts } };
      }
    );

    my $i = 0;

    for my $line ( @{$lines} ) {
      $instance->parser->handle_line( $line, { line => $i } );
      $i++;
    }
    if ( exists $stash{header} ) {
      push @output, { header => $stash{header}, line => $stash{header}->[0]->{line} };
    }
    if ( exists $stash{changeheader} ) {
      push @output,
        {
        change => {
          header => $stash{changeheader},
          body   => ( exists $stash{changebody} ? $stash{changebody} : {} ),
        },
        line => $stash{changeheader}->[0]->{line},
        };
    }
    return [ sort { $a->{line} <=> $b->{line} } @output ];
  }
  __PACKAGE__->meta->make_immutable;
  no Moose;
}
1;

