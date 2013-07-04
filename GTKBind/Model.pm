{ package GTKBind::Model;
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
        class     => ['GTKBind::Model::MetaRole::Class'],
        attribute => ['GTKBind::Model::MetaRole::Attribute'],
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

        $meta->add_attribute(
            '_listeners',
            is       => 'ro',
            isa      => 'HashRef',
            default => sub {{}},
        );

        $meta->add_method( 'reset', sub {
            my $self     = shift;
            my $attrname = shift
              or croak 'Need to be given an attribute name';
            my $attr = $self->meta->get_attribute($attrname)
              or croak "Attribute '$attrname' not found in class";

            $attr->set_value( $self, $attr->userdefault )
              if $attr->has_userdefault;
        });

        $meta->add_method( 'reset_all', sub {
            my $self = shift;
            for my $attr ( $self->meta->get_all_attributes ) {
                $attr->set_value( $self, $attr->userdefault )
                  if $attr->has_userdefault;
            }
        });

        $meta->add_method( 'default', sub {
            my $self     = shift;
            my $attrname = shift
              or croak 'Need to be given an attribute name';
            my $attr = $self->meta->get_attribute($attrname)
              or croak "Attribute '$attrname' not found in class";

            return $attr->userdefault;
        });

        $meta->add_method( 'add_watch', sub {
            my $self = shift;
            my $attrname = shift
              or croak 'Need to be given an attribute name';
            my $handler = shift
              or croak 'Need to be given a watcher method';

            ref $handler eq 'CODE'
              or croak 'Watcher method needs to be a coderef';

            my $attr = $self->meta->get_attribute($attrname)
              or croak "Attribute '$attrname' not found in class";


            push @{$self->_listeners->{$attrname}}, _curry_watcher($attr, $attrname, $handler);
        });
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

            #Move listeners from the meta to the instance.
            $self->_listeners->{$name} = $meta->_listeners->{$name};

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

                for my $listener (@{$self->_listeners->{$attr->name}}) {
                    $listener->($self);
                }
            }
        },

        late        => 1,
        boundto     => [],
        userdefault => $options{default},
    );

    if ( $options{depends} and $options{calculate} and ref $options{calculate} eq 'CODE' ) {
        my $deps = ref $options{depends} eq 'ARRAY' ? $options {depends} : [$options{depends}];
        for my $depends (@{$deps}){
            push @{$meta->_listeners->{$depends}},
              _curry_watcher($attr, $depends, $options{calculate});
        }
    }
    elsif ($options{calculate} && ref $options{calculate} ne 'CODE'){
        carp '"calculate" needs to be a code ref, was instead given a(n) ' .
          ref $options{calculate};
    }
    elsif ($options{depends} xor $options{calculate}){
        carp 'Cannot calculate a value with no dependencies' unless $options{depends};
        carp 'Cannot depend on a value with no calculations' unless $options{calculate};
    }
}

sub _curry_watcher {
    my ($attr, $target, $handler) = @_;
    return sub { $attr->set_value($_[0], $handler->($_[0], $target)) };
}


1;}

{   package GTKBind::Model::MetaRole::Attribute;
    use namespace::autoclean;
    use Moose::Role;

    has 'boundto'     => ( is => 'ro', isa => 'ArrayRef', predicate => 'is_boundto' );
    has 'userdefault' => ( is => 'ro', predicate => 'has_userdefault' );
    has 'late'        => ( is => 'ro', predicate => 'is_late' );

    ##LATE ITEMS ARE LAZY
    before '_process_options' => sub {
        my ( $class, $name, $options ) = @_;
        $options->{lazy} = 1
            if ($options->{late});
    };
1;}


{   package GTKBind::Model::MetaRole::Class;
    use namespace::autoclean;
    use Moose::Role;

    has '_listeners' => (is => 'ro', isa => 'HashRef', default => sub {{}});

    ##INLINED CONSTRUCTOR
    around '_inline_new_object' => sub {
        my ( $method, $self ) = ( shift, shift );

        my @ret = $self->$method(@_);

        splice @ret, -1, 0,
            map {'$instance->meta->get_attribute(\''.$_->name.'\')->get_value($instance);'}
            grep {$_->does('GTKBind::Model::MetaRole::Attribute') && $_->is_late}
            $self->get_all_attributes;

        return @ret;
    };

    ##NOT.. INLINED CONSTRUCTOR
    around 'new_object' => sub {
        my ( $method, $self ) = ( shift, shift );

        my $class = $self->$method(@_);

        $_->get_value($class)
            for grep {$_->does('GTKBind::Model::MetaRole::Attribute') && $_->is_late}
            $self->get_all_attributes;

        return $class;
    };
1;}

