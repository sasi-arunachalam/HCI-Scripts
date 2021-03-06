#!/usr/bin/perl

# script to split fastq files

use strict;
use IO::File;
use File::Basename qw(fileparse);

unless (@ARGV) {
	print <<USAGE;
 
 A simple script to split a gzip-compressed fastq file into subparts.
 Typically used to make aligning monster fastq files easier by splitting
 into independent parallel jobs. 
 This script requires external gzip utility to be in the path.
 Output files named as 0001_file1, 0002_file1, etc. Path and extension 
 are preserved.
 
 Usage: $0 <size> file1.txt.gz file2.txt.gz ...
 
 Where <size> is the maximum number of lines in each part. 
 
USAGE
	exit(0);
}

my $size = shift @ARGV;
unless ($size =~ /^\d+$/) {
	die " must provide an integer for the size!\n";
}
if ($size % 4) {
	die " size must be divisible equally by 4, silly!\n";
}

# process each file
foreach my $file (@ARGV) {
	unless ($file =~ /\.gz$/) {
		die " input file isn't gzipped!!!????\n";
	}
	my $fh = IO::File->new("gzip -dc $file |") or die "unable to read '$file' $!\n";
	
	# prepare parts
	my $part = 1;
	my $base = $file;
	my ($basename, $path, $extension) = fileparse($file, qw(.txt.gz .fastq.gz .fq.gz));
	
	# split file
	my $out = open_output($path, $basename, $extension, $part);
	my $count = 0;	
	while (my $line = $fh->getline) {
		$out->print($line);
		$count++;
		if ($count == $size) {
			# maximum lines attained, close current output filehandle and open another
			$out->close;
			$count = 0;
			$part++;
			$out = open_output($path, $basename, $extension, $part);
		}
	}
	$fh->close;
	$out->close;
	print " split into $part file parts for $file\n";
}


sub open_output {
	my ($path, $basename, $extension, $part) = @_;
	my $filename = $path . $part . '_' . $basename . $extension;
	my $fh = IO::File->new("| gzip >$filename") or 
		die "cannot write to compressed file '$filename' $!\n";
	return $fh;
}
