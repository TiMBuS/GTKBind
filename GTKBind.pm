{ package GTKBind;
use 5.010;
use Moose ();
use MooseX::OmniTrigger;
use Carp;
use Gtk2;

our $VERSION = 0.01;

Moose::Exporter->setup_import_methods(
    also            => ['Moose', 'MooseX::OmniTrigger'],
    with_meta       => [ 'attach' ],
    class_metaroles => {
        class     => ['GTKBind::MetaRole::Class'],
        attribute => ['GTKBind::MetaRole::Attribute'],
    },
);

sub _lookup_default {
    return {
        GtkLabel => ['label', undef],
        GtkEntry => ['text', 'changed'],
    }
}


sub attach {
    my ( $meta, $name, %options ) = @_;

    $options{to} or croak '"attach" needs a widget name to attach "to"';
    my $to = ref $options{to} eq 'ARRAY' ? $options{to} : [$options{to}];

    if ( $options{depends} and $options{calculate} and ref $options{calculate} eq 'SUB' ) {

    }
    elsif ($options{depends} xor $options{calculate}){
        carp 'Cannot calculate a value with no dependencies' unless $options{depends};
        carp 'Cannot depend on a value with no calculations' unless $options{calculate};
        carp '"calculate" needs to be a subroutine' unless ref $options{calculate} eq 'SUB';
    }

    if (!$meta->has_attribute('gui')){
        $meta->add_attribute(
            'gui',
            is       => 'ro',
            isa      => 'Gtk2::Builder',
            required => 1,
        );
    }

    my $attr;
    $attr = $meta->add_attribute(
        $name,
        is => 'rw',
        default => sub {
            my $self = shift;
            my $gui = $self->gui;

            for my $bound (@{$to}) {
                my ($id, $property, $signal, $widget);

                if (ref $bound) {
                    ($id, $property, $signal) = @{$bound}{qw|id property signal|};
                }
                else {
                    $id = $bound;
                }

                $widget =
                    $gui->get_object($id)
                    or carp "Cannot find widget '$id' in builder object!"
                    and next;

                my $widget_type = $widget->get_name;
                $property //=
                    _lookup_default()->{$widget_type}->[0];
                $signal   //=
                    _lookup_default()->{$widget_type}->[1];


                push @{$attr->boundto}, {
                    instance => $widget,
                    property => $property,
                    signal   => $signal
                };

                if ($signal){
                    $widget->signal_connect(
                        $signal,
                        sub {
                            $attr->set_value($self, $widget->get_property($property) );
                        }
                    );
                }
            }

            $options{default};
        },

        omnitrigger => sub {
            ##XXX: REMOVE THIS
            ##say "value changed to $_[2][0]" if $_[2][0];
            my $self = shift;
            my (undef, $new, $old) = @_;

            if (!@{$old} || (@{$new} && $new->[0] ne $old->[0])){
                for my $widget (@{$attr->boundto}) {
                    $widget->{instance}->set_property($widget->{property}, $new->[0]);
                }

                for my $dependant (@{$attr->dependants}) {
                    $dependant->set_value;
                }
            }
        },

        late => 1,
        boundto => [],
    );
}


1;}

{   package GTKBind::MetaRole::Attribute;
    use namespace::autoclean;
    use Moose::Role;

    has 'boundto' => ( is => 'ro', isa => 'ArrayRef', predicate => 'is_boundto' );

    has 'late'    => ( is => 'ro', predicate => 'is_late' );

    ##LATE ITEMS ARE LAZY
    before '_process_options' => sub {
        my ( $class, $name, $options ) = @_;
        $options->{lazy} = 1
            if ($options->{late});
    };
1;}


{   package GTKBind::MetaRole::Class;
    use namespace::autoclean;
    use Moose::Role;

    ##INLINED CONSTRUCTOR
    around '_inline_new_object' => sub {
        my ( $method, $self ) = ( shift, shift );

        my @ret = $self->$method(@_);

        splice @ret, -1, 0,
            map {'$instance->meta->get_attribute(\''.$_->name.'\')->get_value($instance);'}
            grep {$_->is_late}
            $self->get_all_attributes;

        return @ret;
    };

    ##NOT.. INLINED CONSTRUCTOR
    around 'new_object' => sub {
        my ( $method, $self ) = ( shift, shift );

        my $class = $self->$method(@_);

        $_->get_value($class)
            for grep {$_->is_late}
            $self->get_all_attributes;

        return $class;
    };
1;}

