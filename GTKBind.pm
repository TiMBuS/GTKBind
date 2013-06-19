{ package GTKBind;
use 5.010;
use Moose ();
use MooseX::OmniTrigger;
use Carp qw(carp croak);
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
    state $table = {
        GtkLabel => ['label', undef],
        GtkEntry => ['text', 'changed'],
    };
    my $ret = $table->{$_[0]};
    return $ret ? @{$ret} : (undef, undef);
}


sub attach {
    my ( $meta, $name, %options ) = @_;

    $options{to} or croak '"attach" needs a widget name to attach "to"';
    my $to = ref $options{to} eq 'ARRAY' ? $options{to} : [$options{to}];

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
                my ($default_property,$default_signal) = _lookup_default($widget_type);
                $property //= $default_property;
                $signal   //= $default_signal;

                push @{$attr->boundto}, {
                    instance => $widget,
                    property => $property,
                    signal   => $signal,
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

                for my $dependant_callback (@{$self->meta->dependants_map->{$attr->name}}) {
                    $dependant_callback->($self);
                }
            }
        },

        late => 1,
        boundto => [],
    );
    
    if ( $options{depends} and $options{calculate} and ref $options{calculate} eq 'CODE' ) {
        my $deps = ref $options{depends} eq 'ARRAY' ? $options {depends} : [$options{depends}];
        for my $depends (@{$deps}){
            push @{$meta->dependants_map->{$depends}}, sub { $attr->set_value($_[0], $options{calculate}->($_[0], $depends)) };
        }
    }
    elsif ($options{calculate} && ref $options{calculate} ne 'CODE'){
        carp '"calculate" needs to be a code ref, was instead given a ' . ref $options{calculate};
    }
    elsif ($options{depends} xor $options{calculate}){
        carp 'Cannot calculate a value with no dependencies' unless $options{depends};
        carp 'Cannot depend on a value with no calculations' unless $options{calculate};
    }
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
    
    has 'dependants_map' => (is => 'ro', isa => 'HashRef', default => sub {{}});

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

