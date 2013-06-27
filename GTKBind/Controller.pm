{ package GTKBind::Controller;
use 5.010;
use Moose ();
use MooseX::OmniTrigger;
use Carp qw(carp croak);
use Gtk2;

our $VERSION = 0.01;

Moose::Exporter->setup_import_methods(
    also      => [ 'Moose' ],
    with_meta => [ 'event', 'watch' ],
);


sub event {
    state $event_count = 0;
    my ( $meta, $id, $event, $handler ) = @_;
    ref $handler eq 'CODE' or carp 'Need to handle an event/signal with a code reference';

    if (!$meta->has_attribute('gui')){
        $meta->add_attribute(
            'gui',
            is       => 'ro',
            isa      => 'Gtk2::Builder',
            required => 1,
        );

        $meta->add_attribute(
            'model',
            is       => 'ro',
            required => 1,
        );
    }



    my $attr = $meta->add_attribute(
        "${id}_${event}_" . ++$event_count,
        is => 'ro',
        default => sub {
            my $self = shift;

            my $gui = $self->gui;
            my $widget = $gui->get_object($id)
              or carp "Cannot find widget '$id' in builder object!"
              and return;

            return $widget->signal_connect( $event, sub {$handler->($self, @_)} );
        },
    );

    #push {$meta->eventmap} $attr

}

sub watch {
    state $watch_count = 0;
    my ( $meta, $watch_name, $handler ) = @_;
    my $attr = $meta->add_attribute(
        '_watch_' . ++$watch_count,
        default => {

        }
    );
}


1;}
