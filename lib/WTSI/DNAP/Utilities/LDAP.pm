package WTSI::DNAP::Utilities::LDAP;

use namespace::autoclean;
use Net::LDAP;
use List::MoreUtils qw/ uniq /;
use Moose;
use MooseX::StrictConstructor;

with 'WTSI::DNAP::Utilities::Loggable';

our $VERSION = '';

my $host = 'ldap.internal.sanger.ac.uk';

has ldap =>
  (is            => 'ro',
   isa           => 'Net::LDAP',
   required      => 1,
   lazy_build    => 1,
   predicate     => 'has_ldap',
   documentation => 'LDAP connection for retrieving user and group information'
  );
sub _build_ldap {
  my ($self) = @_;
  my $ldap = Net::LDAP->new($host);
  $ldap->bind or $self->logcroak("LDAP failed to bind to '$host': ", $!);
  return $ldap;
}

sub DEMOLISH {
  my ($self) = @_;
  if ($self->has_ldap) {
    $self->ldap->unbind or $self->logwarn("LDAP failed to unbind '$host': ", $!);
  }
  return;
}

sub find_group_ids {
  my ($self) = @_;

  my $query_base   = 'ou=group,dc=sanger,dc=ac,dc=uk';
  my $query_filter = '(cn=*)';
  my $search = $self->ldap->search(base   => $query_base,
                                   filter => $query_filter);
  if ($search->code) {
    $self->logcroak("LDAP query base: '$query_base', filter: '$query_filter' ",
                    'failed: ', $search->error);
  }

  my %group2users;
  my %gid2group;
  foreach my $entry ($search->entries) {
    my $group   = $entry->get_value('cn');
    my $gid     = $entry->get_value('gidNumber');
    my @uids    = $entry->get_value('memberUid');
    $group2users{$group} = \@uids;
    $gid2group{$gid}     = $group;
  }

  return (\%group2users, \%gid2group);
}

sub find_primary_gid {
  my ($self) = @_;

  my $query_base   = 'ou=people,dc=sanger,dc=ac,dc=uk';
  my $query_filter = '(sangerActiveAccount=TRUE)';
  my $search = $self->ldap->search(base   => $query_base,
                                   filter => $query_filter);
  if ($search->code) {
    $self->logcroak("LDAP query base: '$query_base', filter: '$query_filter' ",
                    'failed: ', $search->error);
  }

  my %user2gid;
  foreach my $entry ($search->entries) {
    $user2gid{$entry->get_value('uid')} = $entry->get_value('gidNumber');
  }

  return \%user2gid;
}

sub map_groups_to_users {
  my ($self) = @_;

  my ($group2users, $gid2group) = $self->find_group_ids;
  my $user2gid = $self->find_primary_gid();

  #my @public = ();
  foreach my $uname ( keys %{ $user2gid } ) {
    #push @public, $uname;
    my $gid = $user2gid->{$uname};

    my $primary_group = $gid2group->{$gid};
    # A small number of users may have primary gid of a group not in ldap.
    # (Often the 'nogroup' group)
    # If this is the case, the group obviously does not exist in the
    # group2users hash, so skip the below push.
    if ($primary_group) {
        push @{$group2users->{$primary_group}}, $uname;
    }
  }

  foreach my $group ( keys %{ $group2users } ) {
    my @unames = uniq @{$group2users->{$group}};
    $group2users->{$group} = \@unames;
  }

  return $group2users;
}

sub map_users_to_groups {
  my ($self) = @_;
  my ($group2users, $gid2group) = $self->find_group_ids;
  my $user2gid = $self->find_primary_gid;
  my %user2groups;

  foreach my $uname ( keys %{ $user2gid } ) {
    my @groups;
    push @groups, $gid2group->{$user2gid->{$uname}};

    foreach my $group ( keys %{ $group2users } ) {
      if ( grep(/^$uname$/, @{$group2users->{$group}}) ) {
        push @groups, $group;
      }
    }

    $user2groups{$uname} = \@groups;
  }

  return \%user2groups;
}

sub map_groups_to_emails {
  my ($self, $eml) = @_;

  my $group2users = $self->map_groups_to_users;

  foreach my $group ( keys %{ $group2users } ) {
    foreach my $user ( @{ $group2users->{$group} } ) {
      $user .= $eml || q();
    }
  }
  return $group2users;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=head1 NAME

WTSI::DNAP::Utilities::LDAP

=head1 VERSION


=head1 SYNOPSIS
This module fetches group and user ids from sanger LDAP.

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head2 find_group_ids
 my $ldap = WTSI::DNAP::Utilities::LDAP->new;
 my ($group2users, $gid2group) = $ldap->find_group_ids;
=head3 Returns:
$group2users: reference to hash of group names and usernames of members. Note this does not include members who list this group as their primary group.
                (groupname => (uname1, uname2, ...))
$gid2group: reference to hash of group ids and group names
                (gid => groupname)

=head2 find_primary_gid
 my $ldap = WTSI::DNAP::Utilities::LDAP->new;
 my $user2gid = $ldap->find_primary_gid;
=head3 Returns:
$user2gid: reference to hash of usernames and the gid of their primary group.
                (uname => primary_gid)

=head2 map_groups_to_users
 my $ldap = WTSI::DNAP::Utilities::LDAP->new;
 my $group2users = $ldap->map_groups_to_users;
=head3 Returns:
$group2users: reference to hash mapping group names to array of usernames
                (groupname => (uname1, uname2, ...))

=head2 map_groups_to_emails
 my $ldap = WTSI::DNAP::Utilities::LDAP->new;
 my $group2emails = $ldap->map_groups_to_emails($eml);
=head3 Returns:
$group2users: reference to hash mapping group names to array of emails
              generated by appending domain $eml to usernames. i.e. returned
              emails may not be valid.
                (groupname => (email1, email2, ...))

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item namespace::autoclean

=item Net::LDAP

=item List::MoreUtils

=item Moose

=item MooseX::StrictConstructor

=back

=head1 INCOMPATABILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

=head1 LICENSE AND COPYRIGHT

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
