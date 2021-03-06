#!/usr/bin/perl

# documentation at end of file

use strict;
use Getopt::Long;
use Pod::Usage;
use File::Spec;
use Statistics::Lite qw(mean median);
use Bio::ToolBox::Data;
use Bio::ToolBox::utility;
my $gd_ok;
eval {
	require GD;
	require GD::Graph::smoothlines; 
	$gd_ok = 1;
};
my $VERSION = 1.36;

print "\n This script will graph profile plots of genomic data\n\n";

### Quick help
unless (@ARGV) { # when no command line options are present
	# print SYNOPSIS
	pod2usage( {
		'-verbose' => 0, 
		'-exitval' => 1,
	} );
}



### Get command line options
my (
	$infile, 
	$all, 
	$index, 
	$center, 
	$min, 
	$max, 
	$x_index,
	$dcolor,
	$x_skip,
	$x_offset,
	$x_format,
	$y_format,
	$y_ticks,
	$directory,
	$help,
	$print_version,
);
GetOptions( 
	'in=s'        => \$infile, # the input file
	'index=s'     => \$index, # a list of datasets to graph
	'all'         => \$all, # flag to plot all data sets individually
	'cen!'        => \$center, # flag to center normalize the datasets
	'min=f'       => \$min, # mininum y axis coordinate
	'max=f'       => \$max, # maximum y axis coordinate
	'xindex=i'    => \$x_index, # index of the X-axis values
	'color=s'     => \$dcolor, # data colors
	'skip=i'      => \$x_skip, # number of ticks to skip on x axis
	'offset=i'    => \$x_offset, # skip number of x axis ticks before labeling
	'xformat=i'   => \$x_format, # format decimal numbers of x axis
	'yformat=i'   => \$y_format, # format decimal numbers of y axis
	'ytick=i'     => \$y_ticks, # number of ticks on y axis
	'dir=s'       => \$directory, # optional name of the graph directory
	'help'        => \$help, # flag to print help
	'version'     => \$print_version, # print the version
) or die " unrecognized option(s)!! please refer to the help documentation\n\n";

if ($help) {
	# print entire POD
	pod2usage( {
		'-verbose' => 2,
		'-exitval' => 1,
	} );
}

# Print version
if ($print_version) {
	print " Biotoolbox script graph_profile.pl, version $VERSION\n\n";
	exit;
}



##### Check required and default variables
unless ($gd_ok) {
	die <<GD_WARNING
Modules GD, GD::Graph, and GD::Graph::smoothlines failed to load, either because 
they are not installed or they are missing an external dependency (libgd). 
Please install these to run this script.
GD_WARNING
}

unless ($infile) {
	if (@ARGV) {
		# something left over from the commandline, must be infile
		$infile = shift @ARGV;
	}
	else {
		die " Missing input file!\n Please use --help for more information\n";
	}
}
unless (defined $center) {
	# default is no median center normalization
	$center = 0;
}
unless (defined $x_skip) {
	$x_skip = 1;
}
unless (defined $x_offset) {
	$x_offset = 0;
}
unless (defined $y_ticks) {
	$y_ticks = 8;
}





####### Main ###########

### Load the file
my $Data = Bio::ToolBox::Data->new(file => $infile) or
	die " Unable to load data file!\n";
printf " Loaded %s features from $infile.\n", format_with_commas( $Data->last_row );

# load the dataset names into hashes
my %dataset_by_id; # hashes for name and id
my $i = 0;
foreach my $name ($Data->list_columns) {
	# check column header names for gene or window attribute information
	# these won't be used for graph generation, so we'll skip them
	if ($name =~ /^(?:name|id|class|type|alias|probe|chr|
		chromo|chromosome|seq|sequence|refseq|contig|scaffold|start|stop|end|mid|
		midpoint|strand|primary_id|window|midpoint)$/xi
	) {
		$i++;
		next;
	}
	
	# record the data set name
	$dataset_by_id{$i} = $name;
	$i++;
}	


# find the x index
unless (defined $x_index) {
	find_x_index();
}

# Prepare output directory
unless ($directory) {
	$directory = $Data->path . $Data->basename . '_graphs';
}
unless (-e $directory) {
	mkdir $directory or die "Can't create directory $directory\n";
}


# check colors
my @colors;
if (defined $dcolor) {
	@colors = split /,/, $dcolor;
}


### Get the list of datasets to pairwise compare

# A list of dataset pairs was provided upon execution
if ($index) {
	my @datasets = parse_list($index);
	foreach my $dataset (@datasets) {
		
		# check for multiple datasets to be graphed together
		if ($dataset =~ /&/) {
			my @list = split /&/, $dataset;
			my $check = -1; # assume all are correct initially
			foreach (@list) {
				unless (exists $dataset_by_id{$_}) {
					$check = $_; # remember the bad one
					last; # one at a time, please
				}
			}
			
			# graph the datasets
			if ($check == -1) {
				# all dataset indexes are valid
				graph_this(@list);
			}
			else {
				print " The index '$check' is not valid! Nothing graphed\n";
			}
		}
		
		# single dataset
		else {
			if (exists $dataset_by_id{$dataset}) {
				graph_this($dataset);
			}
			else {
				print " The index '$dataset' is not valid! Nothing graphed\n";
			}
		}
		
	}
}

# All datasets in the input file will be compared to each other
elsif ($all) {
	print " Graphing all datasets individually....\n";
	foreach (sort { $a <=> $b } keys %dataset_by_id) {
		# graph each dataset index alone in incremental order
		graph_this($_);
	}
}

# Interactive session
else {
	graph_datasets_interactively();
}


### The end



##### Subroutines ##########

## Find the x index if possible
sub find_x_index {
	
	# automatically identify the X index if these columns are available
	$x_index = $Data->find_column('^midpoint|start|position$');
	$x_index = $Data->find_column('^window|name$') unless defined $x_index; 
		# we are searching independently because summary files have the window
		# column come before the midpoint column, and we prefer the midpoint
	if (defined $x_index) {
		printf " using %s as the X index column\n", $Data->name($x_index);
		return;
	}
	
	# request from the user
	print " These are the indices of the data file:\n";
	my $i = 0;
	foreach ($Data->list_columns) {
		print "   $i\t$_\n";
		$i++;
	}
	print " Please enter the X index:  \n";
	$x_index = <STDIN>;
	chomp $x_index;
	unless ($Data->name($x_index)) {
		die " Invalid X index!\n";
	}
}





## Subroutine to interact with user and ask for data set pairs to graph sequentially
sub graph_datasets_interactively {
	
	# print messages 
	
	# present the dataset name list
	print " These are the data sets in the file $infile\n";
	foreach (sort {$a <=> $b} keys %dataset_by_id) {
		print "   $_\t$dataset_by_id{$_}\n";
	}
	
	# collect user input
	print " Enter the dataset indices separated by a comma  ";
	my $answer = <STDIN>; # get user answer
	chomp $answer;
	
	# this loop will keep going until no dataset (undefined) is returned
	while ($answer) {
		$answer =~ s/\s*//g;
		my @datasets = parse_list($answer);
		
		# validate the indices
		my $check = -1; # assume all are correct initially
		foreach (@datasets) {
			unless (exists $dataset_by_id{$_} ) {
				$check = $_; # remember the bad one
				last; # one at a time, please
			}
		}
		
		# graph the datasets
		if ($check == -1) {
			# all dataset indexes are valid
			
			graph_this(@datasets);
		}
		else {
			print " The index '$check' is not valid! Nothing graphed\n";
		}
		
		# get ready for next
		print "\n Enter the next set of datasets or push return to exit  ";
		$answer = <STDIN>;
		chomp $answer;
		last if ($answer =~ /^q/i);
	}
}


## Subroutine to graph two given data sets
sub graph_this {
	
	# Retrieve the dataset indices for plotting
	my @datasets = @_;
	
	# Get the name of the datasets
	# join the dataset names together into a string
	my $graph_name = join " & ", map { $dataset_by_id{$_} } @datasets;
	print " Preparing graph for $graph_name....\n";
	
	# shorten if graph name is too long
	if (length $graph_name > 30) {
		# arbitrary length of 30 seems reasonable
		# just use dataset index numbers in this case
		# hell of a lot easier than trying to parse the unique portions of names
		$graph_name = 'datasets_' . join(',', @datasets);
	}
	
	# Collect the values
	my @graph_data; # a complex array of arrays
	
	# first collect the x values, which may be either user defined, the 
	# window midpoint, or the window name
	my @xvalues = $Data->column_values($x_index);
	shift @xvalues; # remove the column header
	push @graph_data, \@xvalues; # push x values as first sub-array
	
	# next collect the dataset values
	foreach my $d (@datasets) {
		my @values;
		$Data->iterate( sub {
			my $row = shift;
			# take only valid values, not nulls
			push @values, $row->value($d) eq '.' ? undef : $row->value($d);
		} );
		push @graph_data, \@values;
	}
	
	
	# Median center the y dataset values if requested
	if ($center) {
		# We will center each Y dataset
		
		foreach my $ydata (1..$#graph_data) {
			# using the index of the graph data sub_arrays
			# skipping the first sub-array, the x values
			
			# determine the median value of this dataset
			my $median_value = median( @{ $graph_data[$ydata] } );
			
			# subtract the median value from each value
			@{ $graph_data[$ydata] } = 
				map { $_ - $median_value } @{ $graph_data[$ydata] };
		}
	}
	
	
	####  Prepare the graph  ####
	
	# Initialize the graph
	my $graph = GD::Graph::smoothlines->new(800,600);
	$graph->set(
		'title'             => 'Profile ' . $Data->feature,
		'x_label'           => $Data->name($x_index),
		'x_label_position'  => 0.5,
		'transparent'       => 0, # no transparency
		'line_width'        => 2,
		'zero_axis'         => 1, 
		'y_tick_number'     => $y_ticks,
		'y_long_ticks'      => 0,
		'y_number_format'   => defined $y_format ? 
								'%.' . $y_format . 'f' : undef, # "%.2f"
		'x_label_skip'      => $x_skip,
		'x_tick_offset'     => $x_offset,
		'x_number_format'   => defined $x_format ? 
								'%.' . $x_format . 'f' : undef, # "%.2f"
	) or warn $graph->error;
	
	# Set the legend
	$graph->set_legend( map { $dataset_by_id{$_} } @datasets ) 
		or warn $graph->error;
	$graph->set('legend_placement' => 'BR') or warn $graph->error; # BottomRight
	
	# Set fonts
	# the default tiny font is too small for 800x600 graphic
	$graph->set_legend_font(GD::Font->MediumBold) or warn $graph->error;
	$graph->set_x_label_font(GD::Font->Large) or warn $graph->error;
	$graph->set_title_font(GD::Font->Giant) or warn $graph->error;
	$graph->set_x_axis_font(GD::Font->Small) or warn $graph->error;
	$graph->set_y_axis_font(GD::Font->Small) or warn $graph->error;
	
	# Set the color if specified
	if (@colors) {
		if (scalar @colors >= scalar @datasets) {
			# user must have set at least the number of colors that we 
			# datasets
			# we are not checking names, presume GD::Graph will do 
			# that for us and complain as necessary
			$graph->set( 'dclrs' => \@colors ) or warn $graph->error;
		}
		else {
			warn " not enough colors provided! using default\n";
		}
	}
	
	# Set min max values on the graph if explicitly defined
	if (defined $min) {
		$graph->set( 'y_min_value' => $min ) or warn $graph->error;
	}
	if (defined $max) {
		$graph->set( 'y_max_value' => $max ) or warn $graph->error;
	}
	# otherwise we let it calculate automatic values
	
	
	# Generate graph file name
	my $filename =  $graph_name . '_profile';
	$filename = File::Spec->catfile($directory, $filename);
	$filename = check_file_uniqueness($filename, 'png');
	
	# Write the graph file
	my $gd = $graph->plot(\@graph_data) or warn $graph->error;
	open IMAGE, ">$filename" or die " Can't open output file '$filename'!\n";
	binmode IMAGE;
	print IMAGE $gd->png;
	close IMAGE;
	
	print " wrote file '$filename'\n";
}



## Make a unique filename
sub check_file_uniqueness {
	my ($filename, $extension) = @_;
	my $number = 1;
	
	# check whether the file is unique
	if (-e "$filename\.$extension") {
		# file already exists, need to make it unique
		my $test = $filename . '_' . $number . '.' . $extension;
		while (-e $test) {
			$number++;
			$test = $filename . '_' . $number . '.' . $extension;
		}
		# found a unique file name
		return $test;
	}
	else {
		# filename is good
		return "$filename\.$extension";
	}
}



__END__

=head1 NAME

graph_profile.pl

A script to graph Y values along a genomic coordinate X-axis.

=head1 SYNOPSIS

graph_profile.pl <filename> 
   
  Options:
  --in <filename>
  --index <index1,index2,...>
  --all
  --cen
  --xindex <index>
  --skip <integer>
  --offset <integer>
  --xformat <integer>
  --min <number>
  --max <number>
  --yformat <integer>
  --ytick <integer>
  --color <name,name,...>
  --dir <foldername>
  --version
  --help

=head1 OPTIONS

The command line flags and descriptions:

=over 4

=item --in <filename>

Specify an input file containing either a list of database features or 
genomic coordinates for which to collect data. The file should be a 
tab-delimited text file, one row per feature, with columns representing 
feature identifiers, attributes, coordinates, and/or data values. The 
first row should be column headers. Text files generated by other 
B<BioToolBox> scripts are acceptable. Files may be gzipped compressed.

=item --index <index>

Specify the column number(s) corresponding to the dataset(s) in
the file to graph. Number is 0-based index. Each dataset should be 
demarcated by a comma. A range of indices may also be specified using 
a dash to demarcate the beginning and end of the inclusive range. 
Multiple datasets to be graphed together should be joined with an ampersand. 
For example, "2,4-6,5&6" will individually graph datasets 2, 4, 5, 6, 
and a combination 5 and 6 graph.

If no dataset indices are specified, then they may be chosen 
interactively from a list.

=item --all

Automatically graph all available datasets present in the file. 

=item --cen

Datasets should (not) be median centered prior to graphing. Useful when 
graphing multiple datasets together when they have different medians. 
Default is false.

=item --xindex <index>

Specify the column index of the X-axis dataset. Unless specified, the 
program automatically uses the columns labeled 'Midpoint' or 'Window', 
if present. 

=item --skip <integer>

Specify the ordinal number of X axis major ticks to label. This 
avoids overlapping labels. The default is 1 (every tick is labeled).

=item --offset <integer>

Specify the number of X axis ticks to skip at the beginning before starting 
to label them. This may help in adjusting the look of the graph. The 
default is 0.

=item --xformat <integer>

Specify the number of decimal places the X axis labels should be formatted. 
The default is undefined (no formatting).

=item --min <number>

=item --max <number>

Specify the minimum and/or maximum values for the Y-axis. The default 
values are automatically determined from the dataset.

=item --yformat <integer>

Specify the number of decimal places the Y axis labels should be formatted. 
The default is undefined (no formatting).

=item --ytick <integer>

Specify explicitly the number of major ticks for the Y axes. 
The default is 8.

=item --color <name,name,...>

Optionally specify the colors for the data lines. The default set 
is lred, lgreen, lblue, lyellow, lpurple, cyan, and lorange. See the 
documentation for L<GD::Graph::colour> for a complete list.

=item --dir

Optionally specify the name of the target directory to place the 
graphs. The default value is the basename of the input file 
appended with "_graphs".

=item --version

Print the version number.

=item --help

Print this help documenation

=back

=head1 DESCRIPTION

This program will generate PNG graphic files representing a profile of 
values plotted along a specific X-axis. For example, plotting values 
along genomic coordinates or relative positions along a feature. The 
X-axis values are static and each dataset is plotted against it. One or 
more datasets may be plotted on a single graph, each in a different 
color, with a legend printed beneath the graph. The graph is a simple 
Bezier-smoothed line graph.

The resulting files are written to a subdirectory named after 
the input file. The files are named after the dataset name (column 
header) with a prefix. 

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Howard Hughes Medical Institute
 Dept of Oncological Sciences
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  
