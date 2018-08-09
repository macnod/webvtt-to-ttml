use MooseX::Declare;

class XOptions {
    use FindBin qw/$Bin/;
    use lib "$Bin";
    use Data::Dumper;
    use Function::Parameters qw/:strict/;
    use Getopt::Long qw/:config bundling/;
    use Text::Wrap qw(wrap $columns $huge);
    use Types::Standard qw/Str Num Int Ref HashRef ArrayRef
                           Any Item RegexpRef CodeRef Undef
                           Bool Maybe Value Object/;
    use Utyls;

    has custom_options => (isa => 'ArrayRef', is => 'rw', default => sub {+[]});
    has all_options => (isa => 'ArrayRef', is => 'rw', lazy => 1,
                        builder => '_all_options_builder');
    has options => (isa => 'HashRef', is => 'rw', lazy => 1,
                    builder => '_options_builder');
    has overview => (isa => 'Str', is => 'ro', default => '');
    has database_options => (isa => 'Bool', is => 'ro', default => 0);
    has u => (isa => 'Utyls', is => 'ro', default => sub {Utyls->new},
              handles => +[qw/
                                 array_contains
                             /]);

    method _all_options_builder () {
        +[
            +{name => 'help',
              type => 'boolean',
              help => 'Show this nice documentation.'},

            (grep {$self->database_options} (

                +{name => 'db-host',
                  short => 'h',
                  type => 'string',
                  help => 'The DNS name or IP address of the database server.'},

                +{name => 'db-port',
                  short => 'P',
                  type => 'integer',
                  default => 3306,
                  help => 'Database server port number.'},

                +{name => 'db-username',
                  short => 'u',
                  type => 'string',
                  help => 'Database user name.'},

                +{name => 'db-password',
                  short => 'p',
                  type => 'string',
                  help => 'Database password.'})),

            @{$self->custom_options}
        ]
    }

    method _options_builder () {
        my $o= +{};
        my @options= @{$self->all_options};
        GetOptions($o, $self->option_specs(\@options));
        if($o->{help}) {print $self->usage, "\n"; exit(1)};
        for my $param (grep {$_->{position}} @{$self->all_options}) {
            if(@ARGV) {
                $o->{$param->{name}}= shift @ARGV;
            }
        }
        my @required= map {$_->{name}}
        grep {
            ((exists $_->{type} && $_->{type} ne 'boolean')
             && !exists $_->{position}
             && (!(exists $_->{default})
                 || $_->{required}
                 || ($_->{required_if}
                     && ref($_->{required_if}) eq 'CODE'
                     && $_->{required_if}->($o))))
        } @options;
        my @missing= grep {!$o->{$_}} @required;
        if(@missing) {
            my $plural= @missing == 1 ? 'option is' : 'options are';
            die "The following required $plural missing: ",
            join(', ', map {"--$_"} @missing), "\n",
                "Use the --help option for more information.\n"}

        my @missing_commands;
        for my $param (grep {$_->{position}} @{$self->all_options}) {
            if(!$o->{$param->{name}} && (
                !(exists $param->{default})
                || $param->{required}
                || ($param->{required_if}
                    && ref($param->{required_if}) eq 'CODE'
                    && $param->{required_if}->($o)))
            ) {
                push @missing, $param->{name};
            }
        }
        if(@missing_commands) {
            die wrap(
                '', '',
                join(
                    ' ',
                    "The following required parameters are missing:",
                    join(", ", @missing) . ".", "Use the --help option for",
                    "more information.")), "\n"}
        for my $option (@options) {
            if(
                exists $option->{default}
                && !exists($o->{$option->{name}})
            ) {
                $o->{$option->{name}}= $option->{default}}}
        $o;
    }

    method build_option_spec (HashRef $option) {
        $option->{name}
        . ($option->{short} ? "|$option->{short}" : '')
        . (exists($option->{type}) && $option->{type} ne 'boolean'
           ? "=" . substr($option->{type}, 0, 1) : '');
    }

    method option_specs (ArrayRef $options) {
        map {$self->build_option_spec($_)} @$options;
    }

    method usage () {
        $Text::Wrap::unexpand= 0;
        $columns= 70;
        $huge= 'wrap';
        my $usage= sprintf("Usage: %s ", $self->u->filename_only($0));
        my @params= grep {$_->{position}} @{$self->all_options};
        $usage.= join(" | ", map {$_->{name}} @params) if @params;
        $usage.= ' options';
        if(grep {$_->{position}} @{$self->all_options}) {
            $usage.= "\n\nParameters:\n" .
            join(
                "\n",
                map {
                    "    $_->{name}\n"
                    . wrap(' ' x 8, ' ' x 8,
                           $self->hsp($_->{help}))
                    . "\n"
                } grep {$_->{position}} @{$self->all_options})
        }
        $usage.= "\n\nOptions:";
        join(
            "\n",
            $usage,
            map {
                "    --$_->{name}"
                . ($_->{short} ? ", -$_->{short}" : '')
                . ($_->{type} ne "boolean" ? " value" : '')
                . ($_->{help} || !exists $_->{default}
                   ? "\n" . wrap(
                       ' ' x 8, ' ' x 8,
                       (exists $_->{default}
                        ? ("Optional.  Defaults to '"
                           . (defined($_->{default})
                              ? $_->{default} : '(undef)')
                           . "'. ")
                        : $_->{type} eq 'boolean'
                        ? "Optional. "
                        : 'Required. ')
                       . ($_->{help} ? $self->hsp($_->{help}) : ''))
                   : '')
                . "\n"
            }
            sort {(exists $a->{required} ? 0 : 1) . $a->{name} cmp
                  (exists $b->{required} ? 0 : 1) . $b->{name}}
            grep {!exists $_->{position}} @{$self->all_options});
    }

    method hsp(Str $s) {
        my $x= $s;
        $x=~ s/\s\s+/ /g;
        $x=~ s/>>>/\n       /g;
        $x=~ s/>>/\n   * /g;
        $x=~ s/<</\n/g;
        $x;
    }

    method BUILD ($) {
        $Text::Wrap::unexpand= 0;
    }
}
