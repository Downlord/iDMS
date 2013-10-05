#!/usr/bin/perl
use POSIX;
use lib('.','/share/Documents/00_Scanner/bin');
#require('/share/Documents/00_Scanner/bin/PDF_Meta.pm');
use PDF_Meta;

#$VERBOSE=1;
#$DEBUG=1;

$null=new PDF_Meta();
$null->truncate_meta();

if($ARGV[0]){
our	$DEBUG=1;
our	$VERBOSE=1;
our $DOCROP=0;

	@files=($ARGV[0]);
}else{
	@files = </share/Documents/00_Scanner/001_Documents/*pdf>;
}


foreach $file (reverse @files) {

	$pdf=new PDF_Meta($file);
	
	
	$pdf->{no_cache}->{size}=1;
	$pdf->{no_cache}->{ocr}=1;
	
	$self->{DOCROP}=1;
	$pdf->{DEBUG}=1;
	
	
	if ( ! -f "$file" ){
		warn("$file existiert nicht".$!);
		next;
	}
	
	print STDERR "parse()\n" if($DEBUG);
	$pdf->parse($file);
	
	print STDERR "get_size()\n" if($DEBUG);
	$pdf->get_size();
	
			
	for($pdf->{current_page}=1;$pdf->{current_page}<=$pdf->{size}->{pages};$pdf->{current_page}++){		
		$pdf->maybe_split_this_pdf();
		last if($self->{split_document}==1);
		
		print STDERR "create_croppic()\n" if($DEBUG);
		$pdf->create_croppic();

		print STDERR "classify()\n" if($DEBUG);
		$pdf->classify();

		print STDERR "read_fields_from_doc()\n" if($DEBUG);
		$pdf->read_fields_from_doc();
		
		print STDERR "guess_content()\n" if($DEBUG);
		$pdf->guess_content();
		
		

	}

	last if($self->{split_document}==1);
	
	
	print STDERR "rename_pdf()\n" if $DEBUG;
	$pdf->rename_pdf();
	
	print STDERR "tag_meta()\n" if $DEBUG;
	$pdf->tag_meta();
	
	print STDERR "write_to_mysql()\n" if $DEBUG;
	$pdf->write_to_mysql();
	
	$pdf->dump_all($DEBUG);
	print STDERR "save_crop_image()\n" if( $DEBUG);
	$pdf->save_crop_image();# if $self->{DOCROP};
	
	#$pdf->unqueue_pdf();
	#exit;
}

	
	