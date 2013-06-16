{package MyModel;
use GTKBind;

attach 'text' => (
	to      => ['entry', 'label'],
	default => 'buttes',
);

attach 'reset_active' => (
	to      => {id => 'resetbutton', property => 'sensitive'},
	default => 0,
);

__PACKAGE__->meta->make_immutable;

1;}





package main;
use 5.010;
use strict;
use warnings;

use Gtk2 '-init';

my $builder = Gtk2::Builder->new();
$builder->add_from_file('test.glade');

my $a = MyModel->new(gui => $builder);

#$a->text('test');


Gtk2->main();
