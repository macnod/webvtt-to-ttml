use Data::Dumper;
use MooseX::Declare;
use FindBin qw($Bin);
use lib "$Bin";

class Utyls {
    use Data::Dumper;
    use List::Util qw/first max maxstr min minstr reduce shuffle sum/;
    use DateTime;
    use DateTime::Format::Duration;
    use Function::Parameters;
    use Switch;
    use Types::Standard qw/Str Num Int Ref HashRef ArrayRef
                           Any Item RegexpRef CodeRef Undef
                           Bool Maybe Value Object/;
    use Scalar::Util qw/looks_like_number/;

    has time_it_indent => (isa => 'Int', is => 'rw', default => 0);

    method slurp (Str $filename) {do {local (@ARGV, $/)= $filename; <>}}

    method slurp_array (Str $filename) {
        (map {s/[\r\n]+$//; $_} (do {local @ARGV= $filename; <>}))}

    method slurp_n_thaw (Str $filename) {$self->thaw($self->slurp($filename))}

    method spew (Str $filename, @data) {
        my $data= join('', @data);
        open(my $fh, '>', $filename) or die $! . " $filename";
        print $fh $data;
        close $fh;
        $data;
    }

    method unique_filename (Str :$directory = '/tmp', Str :$extension = '.tmp') {
        $self->join_paths(
            $directory,
            $self->random_value(8, base => 'alpha_lower')
            . ($extension =~ /^\./ ? $extension : ".$extension"));
    }

    method freeze (Ref $data) {Dumper($data)}

    method thaw (Str $data) {eval('+' . substr($data, 8))}

    method freeze_n_spew (Str $filename, Ref $data) {
        $self->spew($filename, $self->freeze($data));
        $data;
    }

    method clone ($original) {$self->thaw($self->freeze($original))}

    method deeply_equal (Item $a, Item $b) {
        $self->freeze($a) eq $self->freeze($b);
    }

    method merge_hashes (@hashrefs) {
        my $result= +{};
        for my $hashref (@hashrefs) {
            for my $key (keys %$hashref) {
                $result->{$key}= $hashref->{$key}}}
        $result;
    }

    method shuffle_array (@array) {
        shuffle(@array);
    }

    method join_paths (@parts) {
        # Given components of a file path, this method will combine the
        # components to create a file path, inserting or removing '/'
        # characters where necessary.
        my $ds= sum map {defined($_) || 0} @parts;
        unless(@parts > 1 && @parts == $ds) {
            die "You must provide at least 2 strings. You provided " .
            join(", ", map {"'$_'"} @parts) . " => $ds"}
        my @paths;
        push @paths, map {/^(.+)\/?$/; $1} shift @parts;
        push @paths, map {/^\/*(.+)\/?$/; $1} @parts;
        my $path= join('/', grep {defined $_ && $_ ne ''} @paths);
        $path =~ s/([^:])\/\//$1\//g;
        $path
    }

    method filename_only (Str $filename) {
        # Given an absolute filename, this method will return the filename
        # itself, without the path information.
        $filename=~ /([^\/\\]+)$/;
        defined($1) ? $1 : ''
    }

    method path_only (Str $filename) {
        $filename =~ /(.+)\/[^\/]+$/; $1
    }

    method replace_extension (Str $filename, Str $new_extension) {
        my $new_filename= '';
        $new_extension= '' unless defined($new_extension);
        $new_extension= substr($new_extension, 1) if $new_extension =~ /^\./;
        $new_filename= $1 if $filename =~ /^(.*)\.[^. ]+$/;
        if ($new_filename ne '' && $new_extension ne '') {
            $new_filename.= ".$new_extension";
        }
        $new_filename= $filename if $new_filename eq '';
        $new_filename
    }

    method split_n_trim (Str|RegexpRef $separator, Str|Undef $string) {
        # Like split, but returns an array in which each element is trimed
        # of beginning and ending whitespace. The new array also excludes
        # empty strings.
        grep {$_ ne ''}
        map {$_=~ s/^\s+|\s+$//sg; $_}
        split $separator, $string
    }

    method pull_file (
        Str $remote_host,
        Str $remote_file,
        Str $local_file,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$file_contents = 0,
        Bool :$dry_run = 0)
    {
        my $remote= "$remote_host:$remote_file";
        my $env= $password
            ? ('RSYNC_PASSWORD="' . $password . '" ')
            : '';
        my $ssh= $self->ssh('', user => $user, keys => $keys);
        my $rsync= "${env}rsync -v -e '$ssh' $remote $local_file";
        my $result= +{
            command => $rsync,
            remote_path => $remote,
            local_path => $local_file,
        };
        return $result if $dry_run;
        unlink $local_file if -f $local_file;
        my $output= `$rsync 2>&1`;
        my $error= $?;
        $result->{output}= $output;
        $result->{error}= $error;
        if($file_contents) {
            $result->{file_contents}= $self->slurp($local_file)}
        $result;
    }

    method ssh (
        Str $remote_host,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = ''
    ) {
        my @keys= map {"-i $_"} grep {$_} (ref($keys) ? @$keys : ($keys));
        'ssh ' . join(
            ' ', (@keys, "-l $user",
                  '-o UserKnownHostsFile=/dev/null',
                  '-o StrictHostKeyChecking=no',
                  $remote_host));
    }

    method remote_command (
        Str $remote_host,
        Str $command,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = '',
        Bool :$debug = 0,
        Bool :$sudo = 0,
    ) {
        my $cmd= $sudo ? "sudo $command" : $command;
        $cmd=~ s/sudo\s+//s while $cmd && $cmd=~ /(sudo\s+)(sudo\s+)+/;
        my $ssh= $self->ssh(
            $remote_host, user => $user, keys => $keys
        ) . " '$cmd'";
        my $output= $debug ? `$ssh` : `$ssh 2>/dev/null`;
        my $result= +{
            command => $ssh,
            output => (defined($output) ? $output : '')};
        $result->{exit}= $? >> 8;
        $result;
    }

    method remote_file_exists (
        Str $remote_host,
        Str $remote_file,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0
      ) {
        my $cmd= (($sudo ? 'sudo ' : '') . "ls '$remote_file'");
        $cmd=~ s/sudo\s+//s while $cmd && $cmd=~ /(sudo\s+)(sudo\s+)+/;
        my $exists= $self->remote_command(
            $remote_host,
            $cmd,
            user => $user,
            keys => $keys);
        !$exists->{exit};
    }

    method remote_directory_exists (
        Str $remote_host,
        Str $remote_file,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0
      ) {
        my $cmd= (($sudo ? 'sudo ' : '') . "file '$remote_file'");
        $cmd=~ s/sudo\s+//s while $cmd && $cmd=~ /(sudo\s+)(sudo\s+)+/;
        my $exists= $self->remote_command(
            $remote_host,
            $cmd,
            user => $user,
            keys => $keys);
        $exists->{output} =~ /directory\s*$/;
    }

    method delete_remote_file (
        Str $remote_host,
        Str $remote_file,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = ''
    ) {
        if($self->remote_file_exists(
            $remote_host, $remote_file, user => $user, keys => $keys)) {
            $self->remote_command(
                $remote_host, "rm '$remote_file'",
                user => $user, keys => $keys)}
        return;
    }

    method push_file (
        Str $local_file,
        Str $remote_host,
        Str $remote_directory,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$dry_run = 0)
    {
        my $remote= "$remote_host:$remote_directory";
        my $remote_file= $self->join_paths($remote_directory, $local_file);
        my $env= $password
            ? ('RSYNC_PASSWORD="' . $password . '" ')
            : '';
        my $ssh= $self->ssh('', user => $user, keys => $keys);
        my $rsync= "${env}rsync -v -e '$ssh' $local_file $remote";
        my $result= +{
            command => $rsync,
            remote_path => $remote,
            local_path => $local_file,
            error => '',
            exit => '',
        };
        return $result if $dry_run;
        if(
            $self->remote_file_exists(
                $remote_host, $remote_file, keys => $keys)
        ) {
            $result->{delete}= $self->remote_command(
                $remote_host, "rm $remote_file",
                user => $user, keys => $keys);
            $result->{error}= $result->{delete}->{error};
            return $result if $result->{error};
        }
        my $output= `$rsync 2>&1`;
        $result->{exit}= $? >> 8;
        $result->{error}= $result->{exit}
            ? "Error while pushing file: $output"
            : '';
        $result;
    }

    method move_remote_file (
        Str $remote_host,
        Str $source,
        Str $destination,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        my $cmd= ($sudo ? 'sudo ' : '') . "mv $source $destination";
        $cmd=~ s/sudo\s+//s while $cmd && $cmd=~ /(sudo\s+)(sudo\s+)+/;
        $self->remote_command($remote_host, $cmd, user => $user, keys => $keys);
    }

    method copy_remote_file (
        Str $remote_host,
        Str $source,
        Str $destination,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        my $cmd= ($sudo ? 'sudo ' : '') . "cp $source $destination";
        $cmd=~ s/sudo\s+//s while $cmd && $cmd=~ /(sudo\s+)(sudo\s+)+/;
        $self->remote_command($remote_host, $cmd, user => $user, keys => $keys);
    }

    method create_remote_directory (
        Str $remote_host,
        Str $remote_directory,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        unless(
            $self->remote_directory_exists(
                $remote_host, $remote_directory,
                user => $user, keys => $keys,
                sudo => $sudo)
        ) {
            my $cmd= ($sudo ? 'sudo ' : '') . "mkdir $remote_directory";
            $cmd=~ s/sudo\s+//s while $cmd && $cmd=~ /(sudo\s+)(sudo\s+)+/;
            $self->remote_command(
                $remote_host, $cmd, user => $user, keys => $keys);
        }
        return;
    }

    method delete_remote_directory (
        Str $remote_host,
        Str $remote_directory,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        if(
            $self->remote_directory_exists(
                $remote_host, $remote_directory,
                user => $user, keys => $keys,
                sudo => $sudo)
        ) {
            my $cmd= ($sudo ? 'sudo ' : '') . "rm -Rf $remote_directory";
            $cmd=~ s/sudo\s+//s while $cmd && $cmd=~ /(sudo\s+)(sudo\s+)+/;
            return $self->remote_command(
                $remote_host, $cmd, user => $user, keys => $keys);
        }
        return;
    }

    # backup_file must be an absolute path.
    method safe_push_move (
        Str $local_file,
        Str $remote_host,
        Str $remote_file,
        Str $backup_file,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
 Bool :$sudo = 0
    ) {
        my $result;
        if(
            $self->filename_only($local_file) eq
            $self->filename_only($backup_file)
        ) {
            die "File name portion of local_file and backup_file ",
            "must be different.";
        }
        my $staging_path= $self->path_only($backup_file);
        my $staging_filename= $self->join_paths(
            $staging_path,
            $self->filename_only($local_file));

        # Make sure that the remote_backup_dir exists
        $self->create_remote_directory(
            $remote_host,
            $staging_path,
            user => $user,
            keys => $keys);

        # Backup the remote file that we're going to replace
        if(
            $self->remote_file_exists(
                $remote_host, $remote_file,
                user => $user, keys => $keys)
        ) {
            $result= $self->copy_remote_file(
                $remote_host, $remote_file, $backup_file,
                user => $user, keys => $keys, sudo => $sudo);
            return $result if $result->{exit};
        }

        # Delete the file in the staging location
        if(
            $self->remote_file_exists(
                $remote_host,
                $staging_filename,
                user => $user, keys => $keys)
        ) {
            $result= $self->delete_remote_file(
                $remote_host, $staging_filename, user => $user, keys => $keys);
            return $result if $result->{exit};
        }

        # Push the new file to the staging path
        $result= $self->push_file(
            $local_file, $remote_host, $staging_path,
            user => $user, keys => $keys);
        return $result if $result->{exit};

        # Copy the new file to its final destination
        $result= $self->move_remote_file(
            $remote_host, $staging_filename, $remote_file,
            user => $user, keys => $keys, sudo => $sudo);
        return $result if $result->{exit};
        return;
    }

    method log_format (@messages) {
        my $message= join('', @messages);
        $message=~ s/\s+$//sg;
        DateTime->now->datetime() . ' ' . $message . "\n";
    }

    method with_retries (
        Int :$tries = 3,
        Num :$sleep = 1.0,
        Num :$sleep_multiplier = 3.0,
        CodeRef :$logger = sub {},
        Str :$description,
        CodeRef :$action)
    {
        my $result;
        while($tries--) {
            $result= $action->();
            last if $result;
            $logger->("FAILED: $description");
            last unless $tries;
            $logger->("Will try again in $sleep seconds");
            sleep $sleep;
            $sleep*= $sleep_multiplier;
        }
        $result;
    }

#
# Usage: $value= $u->pluck(
#     $merchant_customer,
#     'some-default',
#     qw/profile address zip/);
#
# Purpose: Does roughly the same as the following code:
#
#     if(
#         $merchant_customer
#         && $merchant_customer->profile
#         && $merchant_customer->profile->address
#         && ref($merchant_customer->profile->address) eq 'HASH'
#         && exists $merchant_customer->profile->address->{zip}
#     ) {
#         $value= $merchant_customer->profile->address->{zip}
#     }
#     else {
#         $value= 'some-default';
#     }
#
# In addition to working for objects with methods, the pluck function
# works generally with any nested data structures and is able to tell
# apart methods, hash keys, and array indexes.
#
# Returns: The value at the specified location or, if the value
# doesn't exist or if the location doesn't exist, then the default you
# provided.
#
# Parameters:
#     * $obj: The object or nested data structure
#     * $default: The default value to return if the value isn't found
#     * @path: The path within the object to the location that
#       contains the value you want
#
    method pluck (Item $obj, Item $default, @path) {
        return $default unless defined($obj);
        my ($p, $q);
        eval {
            while(defined($p= shift @path)) {
                if(ref($obj) eq 'HASH' && exists $obj->{$p}) {
                    $obj= $obj->{$p}; next}
                if(
                    ref($obj) eq 'ARRAY'
                    && $p =~ /^[0-9]+$/ && defined $obj->[$p]
                ) {
                    $obj= $obj->[$p]; next}
                if(ref($obj) && ($q= $obj->$p)) {
                    $obj= $q; next}
                $obj= $default;
                last;
            }
        };
        $@ ? (ref($default) eq 'CODE' ? $default->($@) : $default) : $obj;
    }

    method array_contains (Maybe[ArrayRef] $array, Item $item) {
        return 0 unless $array && defined($item);
        my $compare_fn= ref($item) eq 'CODE' ? $item : sub {
            my ($a, $b)= @_; $a eq $b};
        for my $x (@$array) {
            return 1 if $compare_fn->($x, $item);
        }
        return 0;
    }

    method random_value (Int $length, Str :$base_chars= '', Str :$base= '') {
        my %base= (
            hex => join('', (0..9, 'A'..'F')),
            hex_lower => join('', (0..9, 'a'..'f')),
            int => join('', (0..9)),
            base64 => join('', ('A'..'Z', 'a'..'z', 0..9, '/', '+')),
            alpha_upper => join('', 'A'..'Z'),
            alpha_lower => join('', 'a'..'z'),
            octal => join('', 0..7),
            binary => join('', 0..1));
        if($base && !$base{$base}) {
            die "Invalid base specification: '$base'";
        }
        my $b= $base ? $base{$base} : $base_chars ? $base_chars : $base{hex};
        my $count= length($b);
        join('', map {substr($b, int(rand($count)), 1)} (1..$length));
    }

    method flip (Str $p) {
        eval join('', map {$_->{x}} sort {$a->{y} <=> $b->{y}} (
            +{y => 102, x => '='}, +{y => 106, x => 'r'}, +{y => 122,
            x => 'n'}, +{x => 'N', y => 117}, +{x => 'Z', y => 119},
            +{x => ' ', y => 104}, +{x => 'N', y => 128}, +{y => 115,
            x => '-'}, +{x => 'n', y => 111}, +{x => 'm', y => 110},
            +{y => 123, x => '-'}, +{x => '-', y => 109}, +{x => 'p',
            y => 101}, +{y => 127, x => 'm'}, +{x => '-', y => 118},
            +{y => 116, x => 'M'}, +{x => 'M', y => 133}, +{x => '~',
            y => 103}, +{x => '[', y => 107}, +{y => 132, x => '-'},
            +{x => 'a', y => 108}, +{y => 130, x => 'Z'}, +{y => 124,
            x => 'z'}, +{x => ']', y => 134}, +{y => 131, x => 'A'},
            +{y => 125, x => 'a'}, +{y => 121, x => '['}, +{y => 129,
            x => '-'}, +{x => '$', y => 100}, +{y => 120, x => ']'},
            +{x => 'z', y => 113}, +{x => '-', y => 126}, +{y => 105,
            x => 't'}, +{y => 112, x => '-'}, +{y => 114, x => 'A'},
        ));
        $p;
    }

    method subtract_lists (
        ArrayRef $l1,
        ArrayRef $l2,
        CodeRef $equal= sub {$_[0] eq $_[1]}
    ) {
        my @l1= @$l1;
        my @l2= @$l2;
        L2: for my $i2 (0..$#l2) {
              for my $i1 (0..$#l1) {
                  next if not defined($l1[$i1]);
                  if($equal->($l1[$i1], $l2[$i2])) {
                      $l1[$i1]= undef;
                      next L2;
                  }
              }
          }
        grep {defined $_} @l1;
    }

    method expect_keys (Maybe[HashRef] $hash, Maybe[ArrayRef] $expected_keys) {
        $self->missing_keys($hash, $expected_keys) ? 0 : 1;
    }

    method missing_keys (Maybe[HashRef] $hash, Maybe[ArrayRef] $expected_keys) {
        my @available_keys= $hash ? (keys %$hash) : ();
        my @expected_keys= $expected_keys ? @$expected_keys : ();
        $self->subtract_lists(\@expected_keys, \@available_keys);
    }

    method missing_keys_report (
        Maybe[HashRef] $hash,
        Maybe[ArrayRef] $expected_keys
    ) {
        "    Expected: " . join(', ', sort @$expected_keys) . "\n" .
        "         Got: " . join(', ', sort keys %$hash) . "\n" .
        "     Missing: " . join(', ', $self->missing_keys(
            $hash, $expected_keys));
    }

    method choose_one (ArrayRef $a) {
        return undef unless @$a;
        $a->[int(rand @$a)];
    }

    method choose_some (ArrayRef $a, Int $count= 3) {
        return @$a if $count > scalar @$a;
        (shuffle(@$a))[0..$count - 1];
    }

    method render_sql (Str $sql, @values) {
        $sql=~ s/\?/"'" . (shift @values) . "'"/ge;
        $sql;
    }

    method sleep_report (Int $seconds, CodeRef $report) {
        while($seconds--) {
            sleep 1;
            $report->($seconds);
        }
    }

    method every (Maybe[ArrayRef] $array, Str|CodeRef $val) {
        my @matches;
        switch(ref($val)) {
            case 'CODE' {
                for my $item (@$array) {
                    return 0 if !$val->($item);
                }
            }
            case [qw/HASH ARRAY/] {
                for my $item (@$array) {
                    return 0 if $self->deeply_equal($val, $item);
                }
            }
            else {
                if(!defined($val)) {
                    for my $item (@$array) {
                        return 0 if defined($item);
                    }
                }
                elsif(looks_like_number($val)) {
                    for my $item (@$array) {
                        return 0 if $val != $item;
                    }
                }
                else {
                    for my $item (@$array) {
                        return 0 if $val ne $item;
                    }
                }
            }
        }
        1;
    }

    method some (ArrayRef $array, Str|CodeRef $val) {
        !$self->none($array, $val);
    }

    method none (ArrayRef $array, Str|CodeRef $val) {
        switch(ref($val)) {
            case 'CODE' {
                for my $item (@$array) {
                    return 0 if $val->($item);
                }
            }
            case [qw/HASH ARRAY/] {
                for my $item (@$array) {
                    return 0 if $self->deeply_equal($item, $val);
                }
            }
            else {
                if(looks_like_number($val)) {
                    for my $item (@$array) {
                        return 0 if $item == $val;
                    }
                }
                else {
                    for my $item (@$array) {
                        return 0 if $item eq $val;
                    }
                }
            }
        };
        1;
    }

    method any (ArrayRef $array, Str|CodeRef $val) {
        switch(ref($val)) {
            case 'CODE' {
                for my $item (@$array) {
                    return 1 if $val->($item);
                }
            }
            case [qw/HASH ARRAY/] {
                for my $item (@$array) {
                    return 1 if $self->deeply_equal($item, $val);
                }
            }
            else {
                if(looks_like_number($val)) {
                    for my $item (@$array) {
                        return 1 if $item == $val;
                    }
                }
                else {
                    for my $item (@$array) {
                        return 1 if $item eq $val;
                    }
                }
            }
        };
        0;
    }

    method is_prime($x) {
        return 0 if $x < 2;
        return 1 if $x == 2;
        return 0 unless $x % 2;
        for(my $a= 3; $a < sqrt($x); $a+= 2) {
            if($x % $a == 0) {return 0}
        }
        return 1;
    }

    method duration_to_seconds ($x) {
        my @parts= split /:/, $x;
        my $seconds= 0;
        for my $m (1, 60, 3600) {
            $seconds+= @parts ? pop(@parts) * $m : 0;
        }
        $seconds;
    }

    method distinct_elements(
        ArrayRef $a,
        CodeRef $node= sub {$_[0]}
    ) {
        my %h= map {$node->($_) => $_} @$a;
        values %h;
    }

    method distinct_element_counts(
        ArrayRef $a,
        CodeRef $node= sub {$_[0]}
    ) {
        my %h;
        for my $value (@$a) {
            my $key= $node->($value);
            if(exists($h{$key})) {
                $h{$key}->{count}++;
            }
            else {
                $h{$key}= +{value => $value, count => 1};
            }
        }
        %h;
    }

    method find_column_widths (ArrayRef $data) {
        my @columns= keys %{$data->[0]};
        my %row_width= map {$_ => length($_) + 2} @columns;
        for my $row (@$data) {
            for my $column (@columns) {
                if (length($row->{$column} || '') > $row_width{$column}) {
                    $row_width{$column}= length($row->{$column})}}}
        %row_width;
    }

    method hash_array_table (ArrayRef $array, Maybe[HashRef] $column_order) {
        my %row_width= $self->find_column_widths($array);
        my $index= 1;
        $column_order||= +{map {$_ => $index++} keys %row_width};
        my @columns= sort {
            ($column_order->{$a} || 10) <=> ($column_order->{$b} || 10)
        } keys %row_width;
        my $format= '| ' .
            join(' | ', map {'%-' . $row_width{$_} . 's'} @columns) . " |\n";
        my @rows;
        push @rows, sprintf($format, map {"*$_*"} @columns);
        for my $row (@$array) {
            push @rows, sprintf($format, map {
                exists  $row->{$_} ? ($row->{$_} || '') : ''} @columns)}
        join('', @rows);
    }

    method hash_array_table_1 (ArrayRef $array, Maybe[ArrayRef] $column_order) {
        my %row_width= $self->find_column_widths($array);
        my $index= 1;
        $column_order= +{
            map {$_ => $index++} (
                $column_order ? (@$column_order) : (sort keys %row_width))};
        my @columns= sort {
            ($column_order->{$a} || 10) <=> ($column_order->{$b} || 10)
        } keys %row_width;
        my $format= '| ' .
            join(' | ', map {'%-' . $row_width{$_} . 's'} @columns) . " |\n";
        my @rows;
        push @rows, sprintf($format, map {"*$_*"} @columns);
        for my $row (@$array) {
            push @rows, sprintf($format, map {
                exists  $row->{$_} ? ($row->{$_} || '') : ''} @columns)}
        join('', @rows);
    }

    # The following method turns an array into a hash.  If the array
    # contains hash elements, you can specify a key (a scalar value)
    # that's present in all the elements, and this function will
    # create a hash where the keys are the values associated with the
    # specified key in each hash element of the original array.  This
    # is the default behavior.  You can also provide an array
    # reference for the key, in which case this function will evaluate
    # the first element of the key array to determine how it should
    # associate values with the keys.  If you specify an array that
    # looks like ['hash_key' => 'id'], then the function will behave
    # in the default manner described earlier.  If you specify an
    # array that looks like ['array_index' => 12], then this function
    # assumes that the original array contains arrays instead of
    # hashes, and it uses the index specified in the key array (12, in
    # this case) to identify the value from each array in the orignal
    # array that it should use as a key.
    #
    # The assign_value parameter, which is optional, tells the
    # function how to assign values to the keys in the resulting hash.
    # The default is to assume that the values at the given key or
    # index in the elements of the original array are distinct, and
    # to assign a single value to each key in the resulting array.
    #
    # If the values at the given key or index of the original array
    # elements are not distinct (multiple array values have the same
    # value at the specified key or index), then you may want to use
    # the assign_value parameter.  You can provide a string or a
    # function.  If you provide a function, then the function is used
    # to assign the value.  The function you provide will accept 3
    # parameters: (1) A reference to the hash that the function is
    # building; (2) The key that the function is processing; and (3)
    # The element that the function is processing.  The default
    # assign_value function inserts the element into the hash at key.
    # If your original array contains multiple elements that have the
    # value at the specified key, then you may want to change the
    # function to collect multiple elements in an new array at each
    # key of the new hash.
    #
    # Examples:
    # * hash-key (default) behavior
    #     * Code
    #         $x= [
    #             {first => 'Donnie', last => 'Cameron', id => 1},
    #             {first => 'Charles', last => 'Cameron', id => 2},
    #             {first => 'John', last => 'Doe', id => 3}
    #         ];
    #         $u->hashify($x, 'id');
    #         # equivalent: $u->hashify($x, [hash_key => 'id'];
    #     * Result
    #         {
    #             1 => {first => 'Donnie', last => 'Cameron', id => 1},
    #             2 => {first => 'Charles', last => 'Cameron', id => 2},
    #             3 => {first => 'John', last => 'Doe', id => 3}
    #         }
    #     * Notes
    #         The program assumes that each element of the original
    #         array has a distinct id.
    #
    # * array-index behavior
    #     * Code
    #         $x= [
    #             ['Donnie', 'Cameron', 1],
    #             ['Charles', 'Cameron', 2],
    #             ['John', 'Doe', 3]
    #         ];
    #         $u->hashify($x, [array_index => 2]);
    #     * Result
    #         {
    #             1 => {first => 'Donnie', last => 'Cameron', id => 1},
    #             2 => {first => 'Charles', last => 'Cameron', id => 2},
    #             3 => {first => 'John', last => 'Doe', id => 3}
    #         }
    #
    # * assign_value
    #     * Code
    #         $x= [
    #             ['Donnie', 'Cameron', 1],
    #             ['Charles', 'Cameron', 2],
    #             ['John', 'Doe', 3]
    #         ];
    #         $u->hashify(
    #             $x,
    #             [array_index => 1],
    #             assign_value => sub {
    #                 my ($hash, $key, $element)= @_;
    #                 if (exists $hash->{$key}) {
    #                     push @{$hash->{$key}}, $element;
    #                 } else {
    #                     $hash->{$key}= +[$element];
    #                 }
    #             })
    #         # equivalent: $u->hashify($x, [array_index => 1], 'one-to-many');
    #     * Result
    #         {
    #             'Cameron' => [
    #                 {first => 'Donnie', last => 'Cameron', id => 1},
    #                 {first => 'Charles', last => 'Cameron', id => 2}
    #             ],
    #             'Doe' => [
    #                 {first => 'John', last => 'Doe', id => 3}
    #             ]
    #         }
    method hashify (
        ArrayRef $array,
        CodeRef|ArrayRef|Str $key,
        CodeRef|Str $assign_value= ''
    ) {
        unless(ref($assign_value)) {
            switch($assign_value) {
                case 'one-to-many' {
                    $assign_value= sub {
                        my ($hash, $key, $element)= @_;
                        if(exists $hash->{$key}) {
                            push @{$hash->{$key}}, $element;
                        }
                        else {
                            $hash->{$key}= +[$element]}}}
                else {
                    $assign_value= sub {my ($h, $k, $e)= @_; $h->{$k}= $e}}}}
        if(ref($key) eq 'ARRAY') {
            my $mode= $key->[0];
            my $key_or_index= $key->[1];
            switch($mode) {
                case 'array_index' {$key= sub {$_[0]->[$key_or_index]}}
                case 'hash_key' {$key= $key_or_index}
                else {
                    die "Only array_index or hash_key supported for key mode"}}}
        my $hash= +{};
        for my $element (@$array) {
            my $k= ref($key) ? $key->($element) : $element->{$key};
            $assign_value->($hash, $k, $element);
        }
        %$hash;
    }

    method time_it (
        CodeRef $function,
        Str :$description= '',
        Str :$units = 'seconds',
        Bool :$returns_hash = 0,
        Bool :$squelch = 0,
    ) {
        if($description && !$squelch) {
            print $self->log_format(
                ' ' x $self->time_it_indent
                . "STARTED '$description'");
        }
        $self->time_it_indent($self->time_it_indent + 2);
        my $begin= DateTime->now;
        my $rv= +{
            result => ($returns_hash ? +{$function->()} : +[$function->()]),
        };
        $rv->{elapsed}= DateTime->now->subtract_datetime($begin);
        my $d= DateTime::Format::Duration->new(pattern => '%s seconds');
        $self->time_it_indent($self->time_it_indent - 2);
        if($description && !$squelch) {
            print $self->log_format(
                ' ' x $self->time_it_indent
                . sprintf(
                    "FINISHED '$description' in %s.",
                    $d->format_duration($rv->{elapsed})));
        }
        $rv;
    }

    method is_numeric (Str $value) {
        no warnings;
        $value =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/ ? 1 : 0;
    }
}
