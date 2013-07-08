{ package GTKBind::Controller;
use 5.010;
use Moose ();
use MooseX::OmniTrigger;
use Carp qw(carp croak);
use Gtk2;

our $VERSION = 0.01;

Moose::Exporter->setup_import_methods(
    also      => [ 'Moose' ],
    with_meta => [ 'on', 'event', 'watch' ],
);


sub on {
    state $event_count = 0;
    my ( $meta, $widget, $event, $handler ) = @_;
    $widget && $event && $handler or carp "Usage: on <widget_id>, <event>, <handler>";

    return event(
        $meta,
        "${widget}_${event}_" . ++$event_count,
        'widget'  => $widget,
        'event'   => $event,
        'handler' => $handler,
    );
}

sub event {
    my ( $meta, $name, %options ) = @_;
    @options{qw[ widget event handler ]} or carp "A widget, an event, and a handler are required";
    ref $options{handler} eq 'CODE' or carp 'Need to handle an event/signal with a code reference';

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



    return $meta->add_attribute(
        $name,
        is => 'ro',
        default => sub {
            my $self = shift;

            my $gui = $self->gui;
            my $widget = $gui->get_object($options{widget})
              or carp "Cannot find widget '$options{widget}' in builder object!"
              and return;

            return $widget->signal_connect( $options{event}, sub {$options{handler}->($self, @_)} );
        },
    );
}

sub watch {
    state $watch_count = 0;
    my ( $meta, $watch_name, $handler ) = @_;
    my $attr = $meta->add_attribute(
        'z_watch_' . ++$watch_count,
        is => 'ro',
        default => sub {
            my $self  = shift;
            my $model = $self->model;

            $model->add_watch($watch_name, $handler);
        }
    );
}


1;}
