{   package MooseX::Late;
    use Moose ();
    use Moose::Exporter;
    Moose::Exporter->setup_import_methods(
        class_metaroles => {
            class     => ['MooseX::Late::MetaRole::Class'],
            attribute => ['MooseX::Late::MetaRole::Attribute'],
        },
    );
1;}
 
{   package MooseX::Late::MetaRole::Class;
 
    use namespace::autoclean;
    use Moose::Role;
 
    ##INLINED CONSTRUCTOR
    around '_inline_new_object' => sub {
        my ( $method, $self ) = ( shift, shift );
 
        my @ret = $self->$method(@_);
 
        splice @ret, -1, 0,
            map {'$instance->meta->get_attribute(\''.$_->name.'\')->get_value($instance);'}
            grep {$_->does('MooseX::Late::MetaRole::Attribute') && $_->is_late}
            $self->get_all_attributes;
 
        return @ret;
    };
 
    ##NOT.. INLINED CONSTRUCTOR
    around 'new_object' => sub {
        my ( $method, $self ) = ( shift, shift );
 
        my $class = $self->$method(@_);
 
        $_->get_value($class)
            for grep {$_->does('MooseX::Late::MetaRole::Attribute') && $_->is_late}
            $self->get_all_attributes;
        return $class;
    };
1;}
 
{   package MooseX::Late::MetaRole::Attribute;
    use namespace::autoclean;
    use Moose::Role;
 
    has 'late' => ( is => 'ro', predicate => 'is_late' );
 
    ##LATE ITEMS ARE LAZY
    before '_process_options' => sub {
        my ( $class, $name, $options ) = @_;
        $options->{lazy} = 1 if $options->{late};
    };
1;}