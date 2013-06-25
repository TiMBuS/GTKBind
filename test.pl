use 5.010;
use strict;
use warnings;
use MooseX::Declare;

class My::Model {
    use GTKBind::Model;

    attach 'text' => (
        to      => [ 'entry', 'label' ],
        default => 'buttes',
    );

    attach 'reset_active' => (
        to      => { id => 'resetbutton', property => 'sensitive' },
        default => 0,

        depends   => 'text',
        calculate => sub {
            my $self = shift;
            my $val  = shift;    #In this case, it's always 'text'.
            return $self->$val ne $self->default($val);
        }
    );

}


class My::Controller {
    use GTKBind::Controller;
    event 'resetbutton', 'clicked' => sub {
        my $self = shift;
        $self->model->reset('text');
    };
}



use Gtk2 '-init';

my $builder = Gtk2::Builder->new();
$builder->add_from_file('test.glade');

my $a = My::Controller->new( model => My::Model->new( gui => $builder ), gui => $builder );

Gtk2->main();
