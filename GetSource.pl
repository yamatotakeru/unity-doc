#!/usr/bin/perl

# Extraction will cache downloaded wiki pages and converted images in 'wikicache'
# folder. If you want to play around with the conversion script quickly, pass:
#	'-cached' to use cached text + images
#	'-cachedimages' to only use cached images

use strict;
use warnings;
use File::Spec;
use File::Basename;
use URI::Escape;
use URI;
use HTML::Parser;

use FindBin qw'$Bin';

# Check parameters
die "Usage: Extract.pl output_dir [-specific Foo] [-images Suffix] [-cached|-cachedimages|-cachedtext]\n"
	if @ARGV < 1 or ($ARGV[0] eq "--help" or $ARGV[0] eq "-h");

if (`uname -r` =~ /^7/) {
	die "WikiDocs/Extract.pl does not operate correctly on Panther...\n";
}

# Constants
# my $WIKI_URL = 'http://docwiki.hq.unity3d.com';
# my $WIKI_URL = 'http://localhost:8888';
# my $WIKI_URL = 'http://unity.groovesync.com/support/documentation';
# my $WIKI_URL = 'http://docwiki.unity3d.co.jp';
# my $PAGE_TEMPLATE = 'page.tpl.html';
# my $PRINT_TEMPLATE = 'printable.tpl.html';
# my $LINK_INFO = 'link_info.dat';
# our $template = slurp($PAGE_TEMPLATE);
# our $print_template = slurp($PRINT_TEMPLATE);
my $cachetext = 0;
my $cacheimg = 0;
my @specificmodes;
my $imagesuffix = '';


my $EXTRACT_DIR = $ARGV[0];
my $WIKI_URL    = $ARGV[1];


if (grep /^-cachedtext/, @ARGV) {
	print STDERR "WIKI: Cached text mode! All pages will be read from wikicache folder\n";
	$cachetext = 1;
} elsif (grep /^-cachedimages/, @ARGV) {
	print STDERR "WIKI: Cached images mode! All images will be read from wikicache folder\n";
	$cacheimg = 1;
} elsif (grep /^-cached/, @ARGV) {
	print STDERR "WIKI: Cached mode! All pages and images will be read from wikicache folder\n";
	$cachetext = 1;
	$cacheimg = 1;
}

for (my $i=0; $i < @ARGV-1;++$i) {

	if ($ARGV[$i] eq '-specific') {
		push(@specificmodes ,$ARGV[$i+1]);
	}
	if ($ARGV[$i] eq '-images') {
		$imagesuffix = $ARGV[$i+1];
	}
}
my $sizeModes = @specificmodes;

print STDERR "WIKI: '@specificmodes' specific(s) mode(s)\n" if $sizeModes != 0;
print STDERR "WIKI: trying '-$imagesuffix' suffix for images\n" if $imagesuffix ne '';

# Clean up work area
if (-e $EXTRACT_DIR) {
	`rm -R $EXTRACT_DIR`;
}
if (-e '/tmp/adf.jpg') {
	`rm /tmp/adf.jpg 2> /dev/null`;
}
mkdir $EXTRACT_DIR;
mkdir "wikicache";
mkdir "wikicache/images";


my $warn_begin = '<span style=\'font-size: 110%; font-weight: bold; color: yellow; background-color: red; padding: 2px;\'>';
my $warn_end = '</span>';

# Extract the TOC
my $toc = slurp_url( "$WIKI_URL/index.php?n=Main.TableOfContents" );
$toc =~ /<!--PageText-->(.*)<!--PageFooterFmt-->/s;
my $content = $1;

my %page_data; # wiki page title -> data
my %page_ids; # wiki page id -> title


# Loop over TOC links and slurp pages
my $counter = 0;
my $page_limit = 10000;
my $section = '';
my $specific = '';

# look for <div class='specific...> and closing </div> to eliminate platform specific pages
while( $counter < $page_limit && $content =~ /class='specific-(.*?)'|<a class='wikilink' href='(.*?)'>(.*?)<\/a>|(<\/div>)/sg) {
	$counter++;

	if($4) { 
#		print STDERR "found closing div\n";
		$specific = '';
		next;
	}

	if($1) {
#		print STDERR "found specific div:$1\n";
		$specific = $1;
		next;
	}
	
	my $url = $2;
	my $title = $3;
	$url =~ /.*n=Main\.([^\#]+)(.*)/s; #don't want anchor in page id
	my $page_id = $1;

	#if specific is set then we are inside a specific div, so keep ignoring linked pages
	if ($specific) {
		print STDERR "Specific to $specific: ";
		if (!check_specific($specific)) {
			print STDERR "SKIPPING $title\n";
			next;
		}
	}
	
	my $sectionStart = 0;
	my $sectionTitle ='';
	if( $title eq 'Unity Manual' ) {
		$section = 'Manual';
		$sectionTitle = 'Manual';
		$sectionStart = 1;
	} elsif( $title eq 'Reference' ) {
		$section = 'Components';
		$sectionTitle = 'Reference';
		$sectionStart = 1;
	}
	
	my $filename = "$EXTRACT_DIR/$section/$title.html";
	my $linkname = "$section/$title.html";
	if( $sectionStart ) {
		$filename = "$EXTRACT_DIR/$section/index.html";
		$linkname = "$section/index.html";
		print STDERR "Section: $section\n";
	}
	print STDERR "Downloading: $title\n";

	my $human_title = $title;

	# Fetch the wiki page
	# my $in = slurp_url($url);
	slurp_source_url($url);

}


# Utilities

# This is the javascript code that is relevant for folding/unfolding platforms 


sub slurp {
	my ($filename) = @_;
	
	open my $fh, $filename
		or die "Unable to open '$filename' for reading: $!";
	local $/; undef $/;
	return scalar <$fh>;
}


sub replace {
	my ($txtref, $params) = @_;
	
	my $keys = uc join '|', keys %$params;
	my $param_tag = '#';
	$$txtref =~ s/$param_tag($keys)$param_tag/$params->{lc $1}/ge;
}

sub check_specific {
	my $s = shift;
	for( my $i = 0; $i < $sizeModes; $i++) {
		if ($s =~ /^no-/) {
			if( "no-$specificmodes[$i]" ne $s) { # do not include for this platform
				return 1;
			}
		} else {
			if ($specificmodes[$i] eq $s) { # not for this platform
				return 1;
			}
		}
	}
	return 0;
}

sub mkarrow {
	my ($dir, $page) = @_;

	my $human_title;
	if ($dir eq 'next') {
		$human_title = "Next";
	}
	else {
		$human_title = "Previous";
	}

	return qq{
		<div class="nav-$dir">
			<a href='../$page'>
				<div class="nav-left"></div>
				<div class="nav-main">$human_title</div>
				<div class="nav-right"></div>
			</a>
		</div>
	};
}

sub mklink {
	my ($title, $data) = @{$_[0]};
	if ($data) {
		my $human_title = $data->{human_title};
		my $linkname = $data->{linkname};
		return "<a href=\"../$linkname\">$human_title</a>";
	}
	else {
		$title =~ s/^(?:comp-|class-)//;
		return "$title";
	}
}

sub convert_and_resize_image
{
	my ($srcImage, $dstImage) = @_;
	if( $srcImage =~ /^(.*)\.pdf$/i) {
		my $prefix=$1;
        system("$Bin/pdf2jpg", $srcImage);
		unlink($srcImage);
		$srcImage=$prefix.'.jpg';
	}
	
	if ($srcImage eq $dstImage && $srcImage =~ /^(.*)\.gif$/i) {
		my $srcFilename = basename($srcImage);
		print ".";
		return;
	}

	if($srcImage eq $dstImage) {
		my $new = $srcImage;
		$new =~ s/(\.[^.]+)$/_tmp$1/;
		rename($srcImage, $new);
		$srcImage=$new;
	}
	
	my $q=99;
	for($q = 96; $q > 75; $q-=2) {
		system "$Bin/convert", 
			-resize => '550x900>', # Resize to max 550x900 maintaining aspect ratio, don't resize if image is smaller 
			#-unsharp => "0x1.0+0.1", # Perform a unsharp mask on the resized image and apply 40% of it to the original before saving
			-quality => $q,
			-density => 0,
			-interlace => "plane",
			-background => "white",
			"-flatten",
			$srcImage, $dstImage;
#		$? && die "Could not convert image $srcImage";
		$? && die "$srcImage could not convert image $dstImage\n";
#		$? && print STDERR "$srcImage could not convert image $dstImage\n";
		last if -s $dstImage < 102400; # target size is 100Kb if possible;
	}
	my $srcFilename = basename($srcImage);
	print ".";
	unlink($srcImage);
}

sub get_url {
	my ($url, $dest)=@_;
	system('curl', -s => -S => , -o=>$dest, -u=>'docwiki_unity:hU85GfupOc', $url);
	$? && die "Could not download url $url, ";
}

sub try_get_url {
	my ($url, $dest)=@_;
	system('curl', -s => , -f => -o=>$dest, -u=>'docwiki_unity:hU85GfupOc', $url);
	return $? ? 0 : 1;
}

sub slurp_url {
	my ($url)=@_;
	$url =~ /.*\?n=Main\.(.+)/;
	my $cachename = "wikicache/$1.txt";
	if ($cachetext) {
		return slurp( $cachename );
	}
	open my $fh, '-|', 'curl', -s => -S => , -o=>'-', -u=>'docwiki_unity:hU85GfupOc', $url
		or die "Unable to open '$url' for reading: $!";
	local $/; undef $/;
	my $text = scalar <$fh>;
	
	open my $ff, '>', $cachename
		or die "Unable to open '". $cachename . "' for writing: $!\n";
	print $ff $text;
	close $ff;

#gjd
	slurp_source_url($url);
		
	return $text;
}

#gjd
sub slurp_source_url {
	my ($url)=@_;
	$url =~ /.*\?n=Main\.(.+)/;
	my $cachename = "$EXTRACT_DIR/$1.txt";

	open my $fh, '-|', 'curl', -s => -S => , -o=>'-', -u=>'docwiki_unity:hU85GfupOc', $url . "&action=source"
		or die "Unable to open '$url' for reading: $!";
	local $/; undef $/;
	my $text = scalar <$fh>;
	
	open my $ff, '>', $cachename
		or die "Unable to open '". $cachename . "' for writing: $!\n";
	print $ff $text;
	close $ff;
}
