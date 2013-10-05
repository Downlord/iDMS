package PDF_Meta;    # Im objektorientierten Ansatz muss der Namensraum definiert sein, da in Perl jede Klasse ein Namensraum ist

#;use strict;
#use warnings;
use locale;
BEGIN { $Image::ExifTool::configFile = '' }
use Image::ExifTool qw(:Public);

# setlocale(LC_CTYPE,"de_DE.ISO-8859-1");
use open ':encoding(UTF-8)';
use Config::Std;
use POSIX;
use Date::Parse;
binmode( STDOUT, ":utf8" );
use IPC::Semaphore::Concurrency;
my $c = IPC::Semaphore::Concurrency->new('/tmp/PDF_Meta.lock');
if ( !$c->acquire() ) {
		print "IPC Semaphore .. proc already running\n";
		exit;
		}
use Data::Dumper;
{
		local $Data::Dumper::Terse     = 1;
		local $Data::Dumper::Indent    = 3;
		local $Data::Dumper::Useqq     = 1;
		local $Data::Dumper::Deparse   = 1;
		local $Data::Dumper::Quotekeys = 0;
		local $Data::Dumper::Sortkeys  = 1;
		local $Data::Dumper::Useperl   = 1;
		$Data::Dumper::Maxdepth = 5;
		$Data::Dumper::Sortkeys = sub {
				[ sort { $b cmp $a } keys %{ $_[0] } ];
				};

		#warn Dumper($var);
		}
use DBI;
my $dbh = DBI->connect( 'DBI:mysql:DMS;host=storage', 'root', 'admin', { RaiseError => 1 } )
		|| die "Could not connect to database: $DBI::errstr";
$dbh->do('SET NAMES utf8');
$dbh->{'mysql_enable_utf8'} = 1;
my $currentPage_in_Document;
my %config;
my $RCFILE = "/share/Documents/00_Scanner/bin/dispatch.ini";
read_config "$RCFILE" => %config;
#
# Eventuelle
# POD-Inhalte
#
my $croppic = "/tmp/croppic.jpg";
my %categories;
@{ $categories{"Rechnung"} }         = ("Rechnung");
@{ $categories{"Mahnung"} }          = ( "Mahnung", "Pfändung", "Vollstreckung", "Zahlungseri" );
@{ $categories{"Dokumentation"} }    = ("Dokumentation");
@{ $categories{"Schreiben"} }        = ( "Allgemeine Hinweise", "Rechtsbehelfbelehrung", "Rechnung", "Mahnung" );
@{ $categories{"Rechnungseingang"} } = ("Rechnung");
@{ $categories{"Eilsache"} }         = ("Eilsache");
@{ $categories{"Barbeleg"} }         = ( "TENGELMAN", "REWE" );
@{ $categories{"Zahlschein"} }       = ( "Überweisung/Zahlschein" );

sub new($$)    # Prototyp des Konstruktors
{
		my $class = shift @_;
		my $file;
		if ( exists $_[0] )    # Falls nicht anders angegeben, begrüße "world"
		{
				my $file = $_[0];
		} else {
				my $file = "file";
				}
		my $self->{file} = $file;    # Hash-Referenz mit Daten wird erzeugt...
		$self->{no_cache}->{size} = 1;
		$self->{no_cache}->{ocr}  = 1;
		$self->{current_page}     = 1;
		$self->{DEBUG}            = 1;
		$self->{VERBOSE}          = 1;
		$self->{DOCROP}           = 0;
		bless( $self, $class );      # ... mit dem Klassennamen "abgesegnet"...
		return $self;                # ...und zurückgegeben
		}

sub parse($$)                    # Das Ding ändern, das begrüßt wird
{
		my $self = shift @_;         # Objekt annehmen
		my $file = shift @_;
		$self->{config} = %config;
		$self->{file}->{filename} = $file;    # Daten manipulieren...
		chomp( $self->{file}->{fullp} = qx(readlink -f "$self->{file}->{filename}") );
		chomp( $self->{file}->{basen} = qx(basename "$self->{file}->{fullp}") );
		chomp( $self->{file}->{dirn}  = qx(dirname "$self->{file}->{fullp}") );
		$self->{file}->{croppic} = "/tmp/croppic.jpg";
		( $self->{file}->{cropbn} = $self->{file}->{basen} ) =~ s/\.pdf/.jpg/;
		$self->{file}->{cropout}       = "/share/Web/dms-last/i/" . $self->{file}->{cropbn};
		$self->{meta}->{preview_image} = "/dms-last/i/" . $self->{file}->{cropbn};
		$self->{meta}->{preview_tag}   = '<img src="' . $self->{meta}->{preview_image} . '">';
		( $self->{file}->{donedirn} = $self->{file}->{dirn} ) =~ s/001_Documents/999_Originals/;
		$self->{file}->{donefullp} = $self->{file}->{donedirn} . '/' . $self->{file}->{basen};
		print STDERR "start $self->{file}->{fullp}\t=>\t$self->{file}->{donefullp}\n";
		return $self;    # ...geändertes Objekt zurückgeben
		}

sub get_size($$)     # Das Ding ändern, das begrüßt wird
{
		my $self = shift @_;    # Objekt annehmen
		if ( !$self->{no_cache}->{size} ) {
				my $sql = "select val from cache where filename='" . $self->{file}->{basen} . "' and name='size_identify'";
				my $sth = $dbh->prepare($sql);
				$sth->execute();
				my $result = $sth->fetchrow_hashref();
				}
		if ( !$self->{no_cache}->{size} && $result->{val} ) {
				print "*** HIT size_identify\n" if ( $self->VERBOSE );
				$self->{pdfinfo}->{identify} = $result->{val};
		} else {
				print "*** MISS size_identify\n$sql" if ( $self->{VERBOSE} eq 1 );
				print "*** RUN identify\n"           if ( $self->{VERBOSE} eq 1 );
				my $cmd = "identify -verbose \"$self->{file}->{fullp}\"";
				if ( $self->{DOCROP} == 1 ) {
						$self->{pdfinfo}->{identify} = qx($cmd);
						print "*** RUN done\n" if ( $self->{VERBOSE} eq 1 );
						print "*** RUN sql\n"  if ( $self->{VERBOSE} eq 1 );
						my $sth = $dbh->prepare("REPLACE into cache (filename,name,val) values(?,?,?)");
						$sth->execute( $self->{file}->{basen}, 'size_identify', $self->{pdfinfo}->{identify} );
						print "*** RUN done\n" if ( $self->{VERBOSE} eq 1 );
						}
				}
		if ( $self->{pdfinfo}->{identify} =~ m/Resolution: *(([\d\.]+)x([\d\.]+))/gm ) {
				$self->{size}->{dpi}        = $2;
				$self->{size}->{res_string} = $1;
		} else {
				$self->{size}->{dpi}        = 72;
				$self->{size}->{res_string} = "guessed";
				}
		$self->{meta}->{dpi}     = $self->{meta}->{dpi};
		$self->{meta}->{dpi_who} = $self->{meta}->{res_string};
		if ( !$self->{no_cache}->{size} ) {
				$sth = $dbh->prepare( "select val from cache where filename='" . $self->{file}->{basen} . "' and name='pdfinfo'" );
				$sth->execute();
				$result = $sth->fetchrow_hashref();
				}
		if ( !$self->{no_cache}->{size} && $result->{val} ) {
				print "*** HIT pdfinfo\n" if ( $self->VERBOSE eq 1 );
				$self->{pdfinfo}->{raw} = $result->{val};
		} else {

				#print "*** MISS pdfinfo\n" if($VERBOSE);
				my $cmd = "pdfinfo -box \"$self->{file}->{fullp}\"";
				$self->{pdfinfo}->{raw} = qx($cmd);
				my $sth = $dbh->prepare("REPLACE into cache (filename,name,val) values(?,?,?)");
				$sth->execute( $self->{file}->{basen}, 'pdfinfo', $self->{pdfinfo}->{raw} );
				}
		foreach ( split( /\n/, $self->{pdfinfo}->{identify} ) ) {
				if ( $_ =~ /^(.*):\s(.*)$/sgm ) {
						my $k = trim($1);
						my $v = trim($2);
						$self->{pdfinfo}->{$k} = $v;
						}
				}
		foreach ( split( /\n/, $self->{pdfinfo}->{raw} ) ) {
				if ( $_ =~ /^(.*):\s(.*)$/sgm ) {
						my $k = trim($1);
						my $v = trim($2);
						$self->{pdfinfo}->{$k} = $v;
						}
				}
		if ( $self->{pdfinfo}->{raw} =~ m/Page size: *(([\d\.]+) x ([\d\.]+)) (pts)/gm ) {
				$self->{size}->{s}       = $1;
				$self->{size}->{w}->{px} = $2 * 1;
				$self->{size}->{h}->{px} = $3 * 1;
				$self->{size}->{w}->{mm} = to_mm( $self, $2 );
				$self->{size}->{h}->{mm} = to_mm( $self, $3 );
				$self->{meta}->{size}    = $1;
				$self->{meta}->{size_mm} = $self->{size}->{w}->{mm} . ' x ' . $self->{size}->{h}->{mm};
		} else {
				warn("error getting sizes. \nOutput:\n$1");
				return undef;
				}
		if ( $self->{pdfinfo}->{raw} =~ m/Pages: *(.*)$/gsm ) {
				$self->{size}->{pages} = clean($1);
		} else {

				#warn("error getting pages. \nOutput:\n$self->{pdfinfo}->{raw}");
				$self->{size}->{pages} = 1;
				}

		#print "=====================\n";print $self->{size}->{w}->{px};
		if ( !$self->{size}->{w}->{px} ) {
				warn("no width");

				#print Dumper \$self->{size};
				#print "=====================\n";print $self->{size}->{w}->{px};
				exit;
				}
		return $self;    # ...geändertes Objekt zurückgeben
		}

sub rename_pdf() {
		my $self = shift @_;                                                                                                                                                                                                                                                                                                  # Objekt annehmen
		my $date = ( $self->{meta}->{'datum'} ) ? ( $self->{meta}->{'datum'} ) : ( $self->{pdfinfo}->{'Create Date'} ) ? $self->{pdfinfo}->{'date:create:'} : ( $self->{pdfinfo}->{'Create Date'} ) ? $self->{pdfinfo}->{'Create Date'} : ( $self->{pdfinfo}->{'CreationDate'} ) ? $self->{pdfinfo}->{'CreationDate'} : '';
		my ( $ss, $mm, $hh, $day, $month, $year, $zone ) = strptime($date);
		$year += 1900;
		return if ( $year <= 2005 || $year >= 2014 );
		return if ( $month <= 0   || $month >= 13 );
		return if ( $day <= 0     || $day >= 32 );
		$month = printf( "%2d", $month );
		$day   = printf( "%2d", $day );
		my $newfname = "scan_$year" . printf( "%2d", $month ) . printf( "%2d", $day ) . "_$hh$mm${ss}00.pdf";
		my $s_mc = ( $self->{meta}->{match_class} ne "" ) ? $self->{meta}->{match_class} . "_" : "scan_";
		my $s_su = ( $self->{meta}->{subject} ne "" ) ? mysubstr( $self, $self->{meta}->{subject}, 0, 25 ) : "_${hh}${mm}${ss}00";
		my $s_sd = ( $self->{meta}->{sender} ne "" ) ? "_" . mysubstr( $self, $self->{meta}->{sender}, 0, 25 ) : "00";
		$newfname = "${s_mc}${year}-" . printf( "%2d", $month ) . "-" . printf( "%2d", $day ) . "_${s_su}_${s_sd}.pdf";
		$self->{file}->{newbasen} = $newfname;
		( $self->{file}->{newdirn} = $self->{file}->{dirn} ) =~ s/001_Documents/002_Processed/;
		$self->{file}->{newfullf} = wsul( $self->{file}->{newdirn} . '/' . $newfname );

		if ( $self->{meta}->{match_type} = "Barbeleg" ) {
				( $self->{file}->{newfilename} = $self->{file}->{basen} ) =~ s/scan_/quittung_/i;
				$self->{meta}->{newbasen};
		} elsif ( length($newfname) > 20 || $newfname =~ /scan_\d\d\d\d\d\d\d\d_\d\d\d\d\d\d/ ) {
				$self->{file}->{newfilename} = wsul($newfname);
				$self->{meta}->{newbasen};
		} else {
				$self->{file}->{newfilename} = $self->{file}->{basen};
				$self->{meta}->{newbasen};
				}
		return $self;
		}

sub classify($)    # Das Ding ändern, das begrüßt wird
{
		my $self = shift @_;    # Objekt annehmen

		#print Dumper \$self->{size};exit;
		#$VERBOSE;$DEBUG;
		$self->{txt_lay}->{page} = get_ocr( $self, 0, 0, -1, -1, $self->{current_page}, "dokument", "white", "-layout" );
		$self->{txt_raw}->{page} = get_ocr( $self, 0, 0, -1, -1, $self->{current_page}, "dokument", "white", "-raw" );
		warn("############## IS CLASSY ?");

		#warn("pdf empty ?") if($self->{pdftxt}->{page} eq "");
		$self->{txt_lay}->{adressfeld} = no_nl( get_ocr( $self, 0, 130, 300, 100, $self->{current_page}, "addressfield", "red" ) );
		warn("############## IS CACHED ?");
		$self->{txt_lay}->{adressfeld_a} = no_nl( get_ocr( $self, 0, 110, 300, 30, 1, "DIN_A4_A", 'white' ) );
		warn("############## IS CACHED ?");
		$self->{txt_lay}->{adressfeld_b} = no_nl( get_ocr( $self, 0, 70, 300, 30, 1, "DIN_A4_B", 'white' ) );
		if ( $self->{txt_lay}->{adressfeld} =~ m/(Laurisch|Riedel|Schulstrasse|Taimerhof)/gsm ) {
				$self->{meta}->{cover_letter} = "Deckblatt";
				}
		my ( $category, $matches, $needle );
		while ( ( $category, $matches ) = each(%categories) ) {

				#				print STDERR "testing for $category \n";
				foreach $needle (@$matches) {
						$needle = $category if ( $needle eq "" );

						#						print STDERR "   using regex $needle \n";
						if ( $self->{txt_lay}->{page} =~ /\Q$needle\E/gmsi ) {

								#print STDERR "found CLASS $category / $needle\n";
								$self->{meta}->{'match_class'} = $category;
								$self->{meta}->{scan_understood} += 20;
								return;
								}
						}
				}
		$self->{meta}->{match_type} = 'Zahlshein' if ( $self->{meta}->{match_class} = 'Zahlschein' );

		#DINA4_a
		if ( ( $self->{txt_lay}->{adressfeld_a} =~ /(Postfach|Str|Stasse)/i ) ) {
				delete( $self->{txt_lay}->{adressfeld_b} );
				$self->{meta}->{match_type} = 'DIN_A4_A';

				#warn("setting type to DIN_A4_A cause of sender in head");
				$self->{meta}->{absender_f} = $self->{txt_lay}->{adressfeld_a};
				$self->{txt_lay}->{adressfeld} = no_nl( get_ocr( $self, 0, 110, 300, 30, 1, "DIN_A4_A", 'red' ) );

				#DINA4_b
		} elsif ( ( $self->{txt_lay}->{adressfeld_b} =~ /(Postfach|Str|Stasse)/i ) ) {
				delete( $self->{txt_lay}->{adressfeld_a} );
				$self->{meta}->{match_type}    = 'DIN_A4_B';
				$self->{meta}->{absender_f}    = $self->{txt_lay}->{adressfeld_b};
				$self->{txt_lay}->{adressfeld} = no_nl( get_ocr( $self, 0, 70, 300, 30, 1, "DIN_A4_B", 'red' ) );

				#QUittung
		} elsif ( $self->{size}->{w}->{px} <= 250 ) {
				delete( $self->{txt_lay}->{adressfeld_a} );
				delete( $self->{txt_lay}->{adressfeld_b} );
				warn("setting type to Quittung cause < 250 width ($self->{size}->{w}->{px})");
				$self->{txt_lay}->{head} = no_nl( get_ocr( $self, 0, 0, -1, 100, 1, "quitt", "red" ) );
				if ( $self->{txt_lay}->{head} =~ m/REWE/gsm ) {

						#warn("setting type to Quittung cause of REWE in head");
						$self->{meta}->{match_type} = "Barbeleg";
						}
		} elsif ( $self->{txt_lay}->{head} =~ /Überweisung\/Zahlschein/ ) {
				$self->{meta}->{match_type} = "Zahlschein";
		} else {
				$self->{meta}->{match_type} = 'DIN_A4_A';
				}
		return;    # ...geändertes Objekt zurückgeben
		}

sub maybe_split_this_pdf($) {
		my $self = shift @_;    # Objekt annehmen
		print STDERR "  START Page $self->{current_page}\n";
		if ( $self->{meta}->{cover_letter} == "Deckblatt" && $self->{current_page} > 1 ) {
				split_this_pdf( $self, $self->{current_page} );
				$self->{split_document} = 1;
		} else {
				$self->{split_document} = 0;
				}
		return $self->{split_document};
		}

sub split_this_pdf($) {
		my $self   = shift @_;                 # Objekt annehmen
		my $fshort = $self->{file}->{fullp};
		my $page;
		$fshort =~ s/(\d)\.pdf//;
		my $fout1 = $fshort . ( $1 + 1 ) . '.pdf';
		my $fout2 = $fshort . ( $1 + 2 ) . '.pdf';
		print "\n*** splitting PDF at $page into:\n";

		#print " ** $fout1\n";
		#print " ** $fout2\n";
		qx(pdftk "$self->{file}->{fullp}" cat 1-$self->{current_page} output "$fout1");
		qx(pdftk "$self->{file}->{fullp}" cat $self->{current_page}-end output "$fout2");
		qx(rm "$self->{file}->{fullp}");
		exit;
		}

sub read_fields_from_doc($) {
		my $self = shift @_;    # Objekt annehmen
		my $ocr;
		foreach my $elem ( keys %{ $config{ $self->{meta}->{match_type} } } ) {

				#warn("------------\nlooking for $elem \n");
				next if ( $elem =~ /-/ );

				# skip page if not defined type in ini is found
				if ( $elem =~ /(body|header|footer|kopf|wsubject)/ ) {
						if ( $ocr = get_ocr( $self, @{ $config{ $self->{meta}->{match_type} }{$elem} }, $self->{current_page}, "$elem", "white" ) ) {
								$self->{txt_lay}->{$elem} = $ocr;
								}
						if ( $ocr = get_ocr( $self, @{ $config{ $self->{meta}->{match_type} }{$elem} }, $self->{current_page}, "$elem", "white", "-raw" ) ) {
								$self->{txt_raw}->{$elem} = $ocr;
								}
				} else {
						if ( $ocr = get_ocr( $self, @{ $config{ $self->{meta}->{match_type} }{$elem} }, $self->{current_page}, "$elem", "red" ) ) {
								$self->{txt_lay}->{$elem} = $ocr;
								}
						}
				}
		foreach my $field ( ( 'subject', 'sender', 'address' ) ) {
				$self->{txt_lay}->{$field} = no_nl( $self->{txt_lay}->{$field} ) if ( $self->{txt_lay}->{$field} );
				}
		foreach my $field ( ( 'body', 'header', 'footer', 'kopf', 'wsubject' ) ) {
				$self->{txt_lay}->{$field} = $self->{txt_lay}->{$field} if ( $self->{txt_lay}->{$field} );
				}
		return;
		}

sub guess_content($) {
		my $self = shift @_;    # Objekt annehmen

		#print STDERR "get_date()\n" if ( $self->{DEBUG} );
		get_date($self);

		#print Dumper \%self->{meta};exit;
		#print STDERR "get_adressen()\n" if ( $self->{DEBUG} );
		get_adressen($self);

		#print STDERR "get_special()\n" if ( $self->{DEBUG} );
		get_special($self);

		#print STDERR "get_body()\n" if ( $self->{DEBUG} );
		get_body($self);

		#print STDERR "get_numbers()\n" if ( $self->{DEBUG} );
		get_numbers($self);

		#print STDERR "get_subject()\n" if ( $self->{DEBUG} );
		get_subject($self);

		#print STDERR "get_sender()\n" if ( $self->{DEBUG} );
		get_sender($self);

		#print STDERR "draw_grid_overlay()\n" if ( $self->{DEBUG} );
		draw_grid_overlay($self);
		if ( $self->{meta}->{match_type} eq "Barbeleg" || $self->{meta}->{match_class} eq "Barbeleg" ) {
				foreach my $line ( split( /\n/, $self->{meta}->{adressfeld} ) ) {
						if ( $line =~ m/^(  *)*([\w\ :\.-]+)\.?:  *([^\s]+)\s*$/g ) {
								my $v = $3;
								my $k = $2;
								$k =~ s/([^\w]+)//g;
								$self->{meta}->{$k} = $v;
								}
						}
				foreach my $line ( split( /\n/, $self->{txt_lay}->{page} ) ) {
						if ( $line =~ /^ +EUR $/ ) {
								$start = 1;
						} elsif ( $start >= 0 ) {
								if ( $line =~ /^([\p{L}\p{Nd}][\p{L}\p{Nd} ]+)    +([\p{Nd}][\p{Nd} ,]+) [\p{L}\p{Nd}]$/gsmi ) {
										$self->{meta}->{'item'}->{$1} = $2;
										}
								}
						}
				print Dumper $self->{txt_lay}->{page};
				}
		return $self;
		}

sub get_subject($$) {
		my $self = shift @_;    # Objekt annehmen
		##
		## -- SUBJECT
		##
		if ( $self->{txt_lay}->{wsubject} =~ /(Sehr geehr|Guten T)/gsm ) {
				my $last = "";
				my $line = "";
				my $lnr;
				my $nextone;
				my @_betreff = split( /\n/, $self->{txt_lay}->{wsubject} );
				foreach $line ( reverse @_betreff ) {
						print STDERR "SUB: stepping back: $line\n" if $self->{DEBUG};
						if ( $line eq "" ) {
								last if ( $lnr > 0 && $nextone == 1 );
						} else {
								if ( $line =~ /(Sehr geehr|Guten T)/ ) {
										$nextone = 1;
								} elsif ( $nextone == 1 ) {
										$self->{meta}->{subject} = $line . " " . $self->{meta}->{subject};
										print STDERR "SUB: adding line: $line\n" if $self->{DEBUG};
										$lnr++;
										}
								}
						}
				if ( length( $self->{meta}->{subject} ) > 10 ) {
						$self->{meta}->{scan_understood} += 50;
						}
				}
		if ( $self->{meta}->{subject} eq "" ) {
				if ( $self->{pdftxt}->{page} =~ m/([\p{L}\p{Nd} ]+)(Sehr geehr|Guten T)/gsm ) {
						print "found match $1";
						$self->{meta}->{subject} = $1;
						exit;
				} elsif ( $self->{meta}->{subject_w} ne "" ) {
						$self->{meta}->{subject} = $self->{meta}->{subject_w};
				} elsif ( $self->{meta}->{subject_w} ne "" ) {
						$self->{meta}->{subject} = $self->{txt_lay}->{wsubject};
						}
				}
		$self->{meta}->{scan_understood} -= 50 if ( $self->{meta}->{subject} =~ s/(.*) (Sehr geehr|Guten T).*?/$1/gsm );
		$self->{meta}->{subject} = no_nl( $self->{meta}->{subject} );
		return;
		}

sub get_sender($) {
		my $self = shift @_;    # Objekt annehmen
		$self->{meta}->{sender} = $self->{txt_lay}->{adressfeld}   if ( $self->{txt_lay}->{adressfeld} ne "" && $self->{meta}->{sender} eq "" );
		$self->{meta}->{sender} = $self->{txt_lay}->{adressfeld_a} if ( $self->{txt_lay}->{adressfeld} ne "" && $self->{meta}->{sender} eq "" );
		$self->{meta}->{sender} = $self->{txt_lay}->{adressfeld_b} if ( $self->{txt_lay}->{adressfeld} ne "" && $self->{meta}->{sender} eq "" );

		#		if($self->{meta}->{sender} !~ /\d\d\d\d\d/){
		#				warn("found no num in string");
		#				warn($self->{meta}->{sender});
		#				delete ($self->{meta}->{sender});
		#		}
		if ( length( $self->{meta}->{sender} ) >= 80 ) {
				warn("found long line in string");
				warn( $self->{meta}->{sender} );
				delete( $self->{meta}->{sender} );
				}
		if ( $self->{meta}->{sender} =~ /(Laurisch|Riedel|Wilhelm|Schulst)/ ) {
				warn("found myself in string");
				warn( $self->{meta}->{sender} );
				delete( $self->{meta}->{sender} );
				}
		$self->{meta}->{sender} = $self->{meta}->{absender_f} if ( length( $self->{meta}->{absender_f} ) > length( $self->{meta}->{sender} ) );

		#		if($self->{meta}->{sender} !~ /\d\d\d\d\d/){
		#				warn("found no num in string");
		#				warn($self->{meta}->{sender});
		#				delete ($self->{meta}->{sender});
		#		}
		if ( $self->{meta}->{sender} =~ /(Laurisch|Riedel|Wilhelm|Schulst)/ ) {
				warn("found myself in string");
				warn( $self->{meta}->{sender} );
				delete( $self->{meta}->{sender} );
				}
		if ( length( $self->{meta}->{sender} ) >= 80 ) {
				warn("found long line in string");
				warn( $self->{meta}->{sender} );
				delete( $self->{meta}->{sender} );
				}
		if ( check_adresse( $self->{meta}->{sender} ) ) {
				$self->{meta}->{scan_understood} += 25;
				}
		$self->{meta}->{sender} = $self->{meta}->{addr_0} if ( $self->{meta}->{sender} eq "" && $self->{meta}->{addr_0} ne "" );
		$self->{meta}->{sender} = $self->{meta}->{email}  if ( $self->{meta}->{sender} eq "" && $self->{meta}->{email} ne "" );
		$self->{meta}->{sender} = "Unbekannt"             if ( $self->{meta}->{sender} eq "" );
		return;
		}

sub get_special($) {
		my $self = shift @_;                   # Objekt annehmen
		my $hay  = $self->{txt_lay}->{page};
		$self->{meta}->{'Summe'} = $1 if ( $hay =~ /Betrag: Euro, Cent[^\p{L}\p{Nd}]([\p{Nd}\.\,]+)[^\p{L}\p{Nd}]/gsmi );
		$self->{meta}->{'URL'}   = $1 if ( $hay =~ /(http.?:\/\/[\w\.\/]*?)\s/i );
		$self->{meta}->{'URL'}   = $1 if ( $hay =~ /(www\.[\w\.\/]*?)\s/i );
		$self->{meta}->{'URL'}   = $1 if ( $hay =~ /((www\.)*[\w\.\/]*?\.(de|com|net))/gmi );
		$self->{meta}->{'email'} = $1 if ( $hay =~ /([A-Za-z0-9\._%-]+\@[A-Za-z0-9\.-]+\.[A-Za-z]{2,4})/smi );
		if ( $hay =~ /[^\p{L}\p{Nd}]([\p{L}]+nummer:?[^\p{L}\p{Nd}]+([\p{L}\p{Nd}]+))[^\p{L}\p{Nd}]/gsmi ) {
				$self->{meta}->{$2} = $1;
				}
		my $hay = $self->{txt_raw}->{page};
		$self->{meta}->{'Summe'} = $1 if ( $hay =~ /Betrag: Euro, Cent[^\p{L}\p{Nd}]([\p{Nd}\.\,]+)[^\p{L}\p{Nd}]/gsmi );
		$self->{meta}->{'URL'}   = $1 if ( $hay =~ /(http.?:\/\/[\w\.\/]*?)\s/i );
		$self->{meta}->{'URL'}   = $1 if ( $hay =~ /(www\.[\w\.\/]*?)\s/i );
		$self->{meta}->{'URL'}   = $1 if ( $hay =~ /((www\.)*[\w\.\/]*?\.(de|com|net))/gmi );
		$self->{meta}->{'email'} = $1 if ( $hay =~ /([A-Za-z0-9\._%-]+\@[A-Za-z0-9\.-]+\.[A-Za-z]{2,4})/smi );
		if ( $hay =~ /[^\p{L}\p{Nd}]([\p{L}]+nummer:?[^\p{L}\p{Nd}]+([\p{L}\p{Nd}]+))[^\p{L}\p{Nd}]/gsmi ) {
				$self->{meta}->{$2} = $1;
				}
		return;
		}

sub get_body($) {
		my $self = shift @_;    # Objekt annehmen
		my $idx;
		my $line;
		my @_betreff = split( /\n/, $self->{txt_lay}->{page} );
		foreach $line (@_betreff) {
				$idx++;
				if ( $line =~ /(Sehr geehr|Guten T)/ ) {
						$self->{meta}->{titel} = join( '', @_betreff[ ( $idx + 1 ) .. ( $idx + 10 ) ] );
						return;
						}
				}
		}

sub get_numbers($) {
		my $self = shift @_;    # Objekt annehmen
		return;
		}

sub get_date($) {
		my $self = shift @_;                   # Objekt annehmen
		my $hay  = $self->{txt_raw}->{page};
		my $inc  = 0;
		my @dat;
		while ( $hay =~ /, den ([\p{Nd}]{1,2}[\.\, ]+[\p{Nd}]{1,2}[\.\, ]+[\p{Nd}]{2,4})/gsm ) {
				$dat[ $inc++ ] = $1;
				$dat[$inc] = clean_date( $self, $dat[$inc] );
				}
		$self->{meta}->{scan_understood} += 10 if ( $dat[0] ne "" );

		#		while ( $hay =~ /Datum:?\s*?([0-3]{1}[0-9]{1}[\.,][0-1]{1}[0-9]{1}[\.,]20[0-9]{2})/mi ) {
		#				my $dat = "datum_${inc}";
		#				$dat[ $inc++ ] = $1;
		#				}
		#		while ( $hay =~ /Datum:?\s*?([0-3]{1}[0-9]{1}[\.,][0-1]{1}[0-9]{1}[\.,]20[0-9]{2})/mi ) {
		#				my $dat = "datum_${inc}";
		#				$dat[ $inc++ ] = $1;
		#				}
		#		while ( $hay =~ /(, den )*([0-3]{0,1}[0-9]{1}[\.,-][0-1]{1}[0-9]{1}[\.,-]([1-2]{1}[0-9]{3}|[0-9]{2}))/gmsi ) {
		#				my $dat = "datum_${inc}";
		#				$dat[ $inc++ ] = $2;
		#				}
		#		while ( $hay =~ /(,\s*den\s+)*([0-3]{0,1}[0-9]{1}[\.,-][0-1]{1}[0-9]{1}[\.,-]([1-2]{1}[0-9]{3}|[0-9]{2}))/gmsi ) {
		#				my $dat = "datum_${inc}";
		#				$dat[ $inc++ ] = $2;
		#				}
		#		while ( $hay =~ /(,\s*den\s+)(([0-3]{0,1}[0-9]{1})[\.,-]([0-1]{0,1}[0-9]{1})[\.,-]([1-2]{1}[0-9]{3}|[0-9]{2}))/gsmi ) {
		#				my $dat = "datum_${inc}";
		#				$dat[ $inc++ ] = $2;
		#				}
		#		while ( $hay =~ /([0-3]{1}[0-9]{1}[\.\s]+?(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Nov|Dez)[\.\s]+?([1-2][0-9]{3}|[0-9]{2}))/msi ) {
		#				my $dat = "datum_${inc}";
		#				$dat[ $inc++ ] = $1;
		#				}
		while ( $hay =~ /(([0-3][0-9])[\.,]([0-1][0-9])[\.,]([1-2][0-9]{3}|[0-9]{2}))/gsmi ) {
				my $dat = "datum_${inc}";
				$dat[ $inc++ ] = $1;
				}
		while ( $hay =~ /(([0-3]{,1}[0-9])[\.,]([0-1]{,1}[0-9])[\.,]([1-2][0-9]{3}|[0-9]{2}))/gsmi ) {
				my $dat = "datum_${inc}";
				$dat[ $inc++ ] = $1;
				}
		while ( $hay =~ /(erwarten Ihre Zahlung bis zum|fällig|bis zum|bis spätestens zum).+(\d\d*[,\.]\d\d*[,\.]\d\d\d\d)/gsm ) {
				$self->{meta}->{frist} = $2;
				}
		my %seen = ();
		my @r    = ();
		$inc = 0;
		foreach my $a (@dat) {
				unless ( $seen{$a} ) {
						$self->{meta}->{ 'datum_' . $inc++ } = $a;
						$seen{$a} = 1;
						}
				}

		#print Dumper $self->{meta};exit;
		$self->{meta}->{datum} = $self->{meta}->{datum_0} if ( $self->{meta}->{datum_0} ne "" && $self->{meta}->{datum} eq "" );
		return $self;
		}

sub get_adressen($:$) {
		my $self = shift @_;
		my $hay  = $self->{txt_raw}->{header} . $self->{txt_raw}->{footer};

		#return if ( $hay eq "" );
		my $a;
		my @addr;
		while ( $hay =~ /[^\p{L}\p{Nd}]([\p{L} ]+?)(UG|GmbH|OHG|KG|AG|OHG|GmbH & Co. OHG|GmbH & Co. KG)([^\p{L}\p{Nd}]*([\p{L} ]+?)(str\.| Str\.|strasse|Ring|weg|allee)* ([\p{Nd}]{1,3})[^\p{L}\p{Nd}]*?([\p{Nd}]{5})([\p{L} ]+?))*([^\p{L}\p{Nd}]|\p{Nd})/smgi ) {
				my $str = "addr_" . $a++;
				$self->{meta}->{$str} = ws("$1 $2, $3 $4 $5, $6 $7");
				print STDERR "found ADDr: $self->{meta}->{$str}\n";
				}
		$hay = $self->{txt_raw}->{page};
		while ( $hay =~ /[^\p{L}\p{Nd}]([\p{L} ]+?)(UG|GmbH|OHG|KG|AG|OHG|GmbH & Co. OHG|GmbH & Co. KG)([^\p{L}\p{Nd}]*([\p{L} ]+?)(str\.| Str\.|strasse|Ring|weg|allee)* ([\p{Nd}]{1,3})[^\p{L}\p{Nd}]*?([\p{Nd}]{5})([\p{L} ]+?))*([^\p{L}\p{Nd}]|\p{Nd})/smgi ) {
				my $str = "addr_" . $a++;
				$self->{meta}->{$str} = ws("$1 $2, $3 $4 $5, $6 $7");
				print STDERR "found ADDr: $self->{meta}->{$str}\n";
				}
		$hay = $self->{txt_lay}->{page};
		while ( $hay =~ /[^\p{L}\p{Nd}]([\p{L} ]+?)(UG|GmbH|OHG|KG|AG|OHG|GmbH & Co. OHG|GmbH & Co. KG)([^\p{L}\p{Nd}]*([\p{L} ]+?)(str\.| Str\.|strasse|Ring|weg|allee)* ([\p{Nd}]{1,3})[^\p{L}\p{Nd}]*?([\p{Nd}]{5})([\p{L} ]+?))*([^\p{L}\p{Nd}]|\p{Nd})/smgi ) {
				my $str = "addr_" . $a++;
				$self->{meta}->{$str} = ws("$1 $2, $3 $4 $5, $6 $7");
				print STDERR "found ADDr: $self->{meta}->{$str}\n";
				}

		#print Dumper \$self->{txt_lay} ;
		#print Dumper \$self->{txt_raw} ;
		return;
		}

sub check_adresse($$) {
		my $self = shift @_;
		my $hay  = shift @_;
		if ( $hay =~ /[^\p{L}\p{Nd}]([\p{L}\p{Nd} ]+)(UG|GmbH|OHG|KG|AG|OHG|GmbH & Co. OHG|GmbH & Co. KG)*[^\p{L}\p{Nd}]*([\p{L}\p{Nd} ]+)(str\.| Str\.|strasse|Ring|weg|allee)* ([\p{Nd}]+)[^\p{L}\p{Nd}]*(\p{Nd}{5})([\p{L} ]+)([^\p{L}\p{Nd}]|\p{Nd})/smgi ) {
				return 1;
		} else {
				return 0;
				}
		}

sub clean_date($) {
		my $self = shift @_;
		my $date = shift @_;
		$date =~ s/([^\p{L}\p{Nd}]| )+/./g;
		print "$date";
		if ( str2time($date) ) {
				my ( $ss, $mm, $hh, $day, $month, $year, $zone ) = strptime($date);
				$year += 1900;
				$month = printf( "%2d", $month );
				return "${day}.${month}.$year";
		} else {
				return $date;
				}
		}

sub check_date($) {
		my $self = shift @_;
		my $date = shift @_;
		return ( str2time($date) ) ? 1 : 0;
		}

sub get_ocr($$$$$$$;$)    # Das Ding ändern, das begrüßt wird
{
		my $self    = shift @_;
		my $x       = shift @_;
		my $y       = shift @_;
		my $w       = shift @_;
		my $h       = shift @_;
		my $page    = shift @_;
		my $name    = shift @_;
		my $mycolor = shift @_;
		my $raw     = shift @_;
		$raw = '-layout' if ( $raw eq "" );
		my ( $package, $filename, $line ) = caller;
		$page = $self->{current_page} if ( $page == 0 );
		my $sth = $dbh->prepare( "select val from cache where filename='" . $self->{file}->{basen} . "' and name='" . $name . $raw . "'" );
		$sth->execute();
		my $result = $sth->fetchrow_hashref();

		if ( $self->{no_cache}->{ocr} ne 1 && $result->{val} ) {
				warn("############## YES YES YES CACHED");
				return ( $result->{val} );
				}
		my $retval;
		my $cmd;
		$mycolor = 'red' if ( $mycolor eq "" );

		#$mycolor = 'red' if ( $mycolor eq "" );
		#return $self->{crop}->{cache}->{$name} if ( $self->{crop}->{cache}->{$name} );
		$self->{crop}->{mycolor}->{$name} = "red" if ( !$self->{crop}->{mycolor}->{$name} );
		$retval = undef;
		if ( $page < 0 ) {
				$page = 1;
				}
		if ( $y < 0 || $y > $self->{size}->{h}->{px} ) {
				$y = ( $self->{size}->{h}->{px} + $y );
				}
		if ( $x < 0 || $x > $self->{size}->{w}->{px} ) {
				$x = ( $self->{size}->{w}->{px} + $x );
				}
		if ( $h < 0 || $h > $self->{size}->{h}->{px} ) {
				$h = $self->{size}->{h}->{px} + $h;
				}
		if ( $w < 0 || $w > $self->{size}->{w}->{px} ) {
				$w = $self->{size}->{w}->{px} + $w;
				}
		$x    = floor($x);
		$y    = floor($y);
		$w    = floor($w);
		$h    = floor($h);
		$page = floor($page);
		if ( "$x$y$w$h$page" !~ m/^[\d\s\.]+$/ ) {
				warn("cropsize not ok: x:$x y:$y w:$w h:$h page:$page");
				return undef;
				}
		my $txtx = ( $x + $w ) / 10 * 8;
		my $txty = ( $y + $h ) - 10;
		my $ws   = $w - 1;
		my $hs   = $h - 1;
		warn("############## NOT NOT  CACHED ?");
		if ( $raw eq "" ) {
				$raw = '-layout';
				}
		if ( $mycolor ne "white" ) {

				#if ( $self->{DOCROP} eq 1 ) {
				print "**\n** $x,$y,$w,$h,$page,$name,$mycolor\n**\n";
				$cmd = "mogrify -region \"${ws}x${hs}+${x}+${y}\" -fill $mycolor -colorize 8% $self->{file}->{croppic}";
				qx($cmd);    # or warn($cmd);
				$cmd = "mogrify -fill none -stroke $mycolor -strokewidth 2  -draw \"rectangle $x, $y, ${ws}, ${hs}\"   $self->{file}->{croppic}";
				qx($cmd);    # or warn($cmd);

				#$cmd = "mogrify -density 40 -fill none -stroke $mycolor -draw \"text $txtx, $txty  '$name - $x x $y / $w x $h'\" $self->{file}->{croppic}";
				$cmd = "mogrify -density 50 -fill none -stroke $mycolor -draw \"text $txtx, $txty  '$name'\" $self->{file}->{croppic}";
				qx($cmd);    # or warn($cmd);
				}
		$cmd = "pdftotext -q -enc UTF-8 -eol unix -nopgbrk $raw -r 72 -f $page -l $page -x $x -y $y -W $w -H $h '$self->{file}->{fullp}' -";

		#print STDERR "$cmd\n";
		$cmd                            = qx($cmd);
		$self->{crop}->{cache}->{$name} = $cmd;
		$sth                            = $dbh->prepare("REPLACE into cache (filename,name,val) values(?,?,?)");
		my $out = $self->{pdfinfo}->{raw} . $self->{pdfinfo}->{identify};
		$sth->execute( $self->{file}->{basen}, $name . $raw, $self->{crop}->{cache}->{$name} );
		return $self->{crop}->{cache}->{$name};
		}

sub get_geometry() {
		my $x = shift;
		my $y = shift;
		my $w = shift;
		my $h = shift;
		return "${w}x${h}+${x}+${y}";
		}

sub create_croppic($) {

		#gs -q -dQUIET -dSAFER -dBATCH -dNOPAUSE -dNOPROMPT -dMaxBitmap=500000000 -dAlignToPixels=0 -dGridFitTT=2 -sDEVICE=pngalpha -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -r72x72 -sOutputFile=/tmp/magick-bOLyMToB-%08d -f/tmp/magick-JHuULSP5 -f/tmp/magick-p-gMI4gA
		my $self = shift @_;

		#return if ( $self->{DOCROP} != 1 );
		warn("#######");
		my ( $package, $filename, $line ) = caller;
		$croppic = "/tmp/croppic";
		if ( -f $croppic ) {
				## CACHED ?
				print STDERR "cached image found .. reusing\n";
				$self->{file}->{croppic} = "/tmp/croppic.jpg";
				return 2;
				}
		print STDERR "generating thumbnail for page $self->{current_page} ..";
		my $cmd = "pdftocairo -singlefile -r 72 -f $self->{current_page} -l $self->{current_page} -jpeg -gray $self->{file}->{fullp} $croppic";
		print STDERR "\n\nusing $cmd \n\n";

		#print $cmd;
		qx($cmd);
		print " done!\n";
		$self->{file}->{croppic} = "/tmp/croppic.jpg";
		if ( !-f $self->{file}->{croppic} ) {
				print STDERR "ERROR on creating croppic with:\n$cmd";
				exit;
				return 1;
		} else {
				return 0;
				}
		}

sub uniq {
		my $self = shift @_;
		return keys %{ { map { $_ => 1 } @_ } };
		}

sub to_px($$)    # Das Ding ändern, das begrüßt wird
{
		my $self = shift @_;
		my $size = shift @_;
		return floor( $size * ( $self->{size}->{dpi} ) / 25.4 );
		}

sub to_mm($$)    # Das Ding ändern, das begrüßt wird
{
		my $self = shift @_;
		my $size = shift @_;
		return floor( $size / $self->{size}->{dpi} * 2.54 * 10 );
		}

sub draw_grid_overlay($)    # Das Ding ändern, das begrüßt wird
{
		my $self = shift @_;

		#return if ( $self->{DOCROP} ne 1 );
		#print "$self->{size}->{w}->{mm} mm\n";
		#print "$self->{size}->{h}->{mm} mm\n";
		#print " DPI: " . $self->{size}->{dpi} . " " . $self->{size}->{res_string} . "\n";
		my $loc;
		my $pw    = $self->{size}->{w}->{px};
		my $h105  = to_px( $self, 105 );
		my $h210  = to_px( $self, 210 );
		my $h13rd = $self->{size}->{h}->{px} / 3;
		my $h23rd = $self->{size}->{h}->{px} / 3 * 2;
		$self->{meta}->{mark1} = "40,$h105,$h210";
		$self->{meta}->{mark2} = "40,$h13rd,$h23rd";
		draw_horizontal_line( $self, 40,     "top",          "violet", 1 );
		draw_horizontal_line( $self, $h105,  "1/3 - $h105",  "violet", 1 );
		draw_horizontal_line( $self, $h210,  "2/3 - $h210",  "violet", 1 );
		draw_horizontal_line( $self, $h13rd, "1/3 - $h13rd", "blue",   1 );
		draw_horizontal_line( $self, $h23rd, "2/3 - $h23rd", "blue",   1 );

		for ( my $ny = 100; $ny < $self->{size}->{h}->{px}; $ny += 100 ) {
				draw_horizontal_line( $self, $ny, "raster - $ny", "black", 1, "left" );
				}
		my $string = $self->{size}->{w}->{px} . " px x " . $self->{size}->{h}->{px} . " px / ";
		$string .= $self->{size}->{w}->{mm} . " mm x " . $self->{size}->{h}->{mm} . " mm ";
		$string .= " DPI: " . $self->{size}->{dpi} . " " . $self->{size}->{res_string};
		draw_horizontal_line( $self, ( $self->{size}->{h}->{px} - 10 ), $string, "black", 1 );
		}

sub draw_horizontal_line($$$$) {
		my $self  = shift @_;
		my $pos   = shift @_;
		my $name  = shift @_;
		my $color = shift @_;
		my $size  = shift @_;
		my $left  = shift @_;

		#return if ( $self->{DOCROP} ne 1 );
		if ( $self->{size}->{w}->{px} eq "" ) {
				warn("doc size unknown");
				print Dumper $self->{size};
				exit;
				}
		my $width = $self->{size}->{w}->{px};
		my $txtx  = ($left) ? 20 : ( $self->{size}->{w}->{px} ) / 10 * 9;
		my $txty  = ( $pos - 10 );
		$color = "black" if ( $color eq "" );
		$self->{file}->{croppic} = "/tmp/croppic.jpg";
		die("no temp croppic $self->{file}->{croppic}") if ( !-f $self->{file}->{croppic} );
		my $cmd = "mogrify -stroke $color -strokewidth 2 -draw \"line 0,$pos,$self->{size}->{w}->{px},$pos\" $self->{file}->{croppic}";
		qx($cmd);
		my $cmd = "mogrify -fill none -density 40 -stroke $color -draw \"text $txtx, $txty  '$name'\" " . $self->{file}->{croppic};
		qx($cmd);
		die("no temp croppic $self->{file}->{croppic}") if ( !-f $self->{file}->{croppic} );
		return;
		}

sub draw_ocr_region($)    # Das Ding ändern, das begrüßt wird
{
		my $self = shift @_;
		my $crop = shift @_;

		#return if ( $self->{DOCROP} ne 1 );
		$self->{c} = $crop;
		my $cmd = "mogrify -region \"$self->{size}->{ws}x$self->{size}->{hs}+$self->{size}->{x}+$self->{size}->{y}\" -fill $self->{crop}->{mycolor} -colorize self->{conf}->{reg_saturation}% $self->{file}->{croppic}";
		qx($cmd);
		}

sub begr_in_string($)     # Die erzeugte Begrüßung als String zurückgeben (z.&nbsp;B. Verwendung mit print()
{
		my $self = shift @_;
		return "Hello $self->{ding}!\n";
		}

sub save_crop_image($) {
		my $self = shift @_;

		#return if ( $self->{DOCROP} ne 1 );
		if ( -f $self->{file}->{cropout} ) {
				warn("ERROR $self->{file}->{cropout} exists !");
				}
		qx(mv -f $self->{file}->{croppic} $self->{file}->{cropout} 2>&1);
		if ( !-f $self->{file}->{cropout} ) {
				warn("ERROR $self->{file}->{cropout} dont exists !\n\n$cmd");
				#exit;
				}

		#print "$self->{file}->{croppic} $self->{file}->{cropout}\n";
		#exit;
		return $?;
		}

sub error($) {
		warn( "**** ERROR ***** " . @_ );
		exit;
		}

sub clean($) {
		my $input = shift @_;
		$input =~ s/^\s+//g;
		$input =~ s/[\r\n]+//gsm;
		$_ =~ s/^[ \n\r\t]+[^\s]{,2}[ \n\r\t]+//gsm;
		$_ =~ s/^[ \n\r\t]+//gsm;
		$_ =~ s/[ \n\r\t]+$//gsm;
		$_ =~ s/[ \n\r\t]+.[ \n\r\t]+$//gsm;
		$_ =~ s/[ \n\r\t]+$/ /gsm;
		$_ =~ s/(?<=(?<![\p{L}\p{Nd}])[\p{L}\p{Nd}]) (?=[\p{L}\p{Nd}](?![\p{L}\p{Nd}]) )//gi;
		return $input;
		}

sub trim() {
		$_ = scalar shift;
		$_ =~ s/[^\p{L}\p{Nd} \n]+/ /gsm;
		$_ =~ s/  +/ /gsm;

		#$_ =~ s/^[ \n\r\t]+[^\s]{,2}[ \n\r\t]+//gsm;
		$_ =~ s/^[ \n\r\t]+//gsm;
		$_ =~ s/[ \n\r\t]+$//gsm;
		$_ =~ s/[ \n\r\t]+.[ \n\r\t]+$//gsm;

		#print "================================\n";
		#print $_;
		#print "================================\n";
		return $_;
		}

sub ws() {
		$_ = scalar shift;
		$_ =~ s/  +/ /gsm;
		$_ =~ s/ ,/,/gsm;
		return $_;
		}

sub wsul() {
		$_ = scalar shift;
		$_ =~ s/  */_/gsm;
		return $_;
		}

sub no_nl() {
		$_ = scalar shift;
		$_ =~ s/[^\p{L}\p{Nd} ]/ /gsm;
		$_ =~ s/  +/ /gsm;
		return $_;
		$_ =~ s/[\n\r]+$/ /gsm;
		return $_;
		}

sub write_to_mysql() {
		my $self = shift @_;
		$dbh->do('SET NAMES utf8');
		$dbh->{'mysql_enable_utf8'} = 1;
		my $sth2 = $dbh->prepare("REPLACE into live_meta (filename,k,v) values(?,?,?)");
		my $sth  = $dbh->prepare("REPLACE into meta (filename,k,v) values(?,?,?)");
		foreach my $k ( keys %{ $self->{meta} } ) {
				next if ( $k =~ /(body|header|footer|kopf)/ );
				if ( $self->{file}->{basen} ne "" && $k ne "" && $self->{meta}->{$k} ne "" ) {
						$sth->execute( $self->{file}->{basen}, $k, $self->{meta}->{$k} ) or die $dbh->errstr();

						#$sth2->execute( $self->{file}->{newbasen}, $k, $self->{meta}->{$k} ) or die $dbh->errstr();
						#			}else{
						#				warn("**ERROR** empty: $self->{file}->{basen} | $k | $self->{meta}->{$k}\n");
						#				print Dumper $k;
						#				print Dumper \$self->{file};
						#				exit;
						#				print Dumper \$self->{meta}->{$k};
						#			}
						}
				}
		$sth = $dbh->prepare("REPLACE into ocr_scans (filename,meta_data) values(?,?)");
		my $out = $self->{pdfinfo}->{raw} . $self->{pdfinfo}->{identify};
		$sth->execute( $self->{file}->{basen}, $out );
		}

sub truncate_meta() {
		my $self = shift @_;

		#$dbh->do('SET NAMES utf8');
		#$dbh->{'mysql_enable_utf8'} = 1;
		#my $sth = $dbh->prepare("TRUNCATE TABLE meta");
		#qx(rm /share/Web/dms-last/i/*png 2>/dev/null);
		#$sth->execute();
		return;
		}

sub tag_meta() {
		my $self     = shift @_;
		my $ExifTool = new Image::ExifTool;
		$ExifTool->Options( Charset => 'UTF8' );

		# delete all but EXIF tags
		#$exifTool->SetNewValue('*');  # delete all...
		foreach my $k ( keys %{ $self->{meta} } ) {
				%Image::ExifTool::UserDefined => 'Image::ExifTool::XMP::pdfx' => $k => {};
				my ( $out, $err ) = $ExifTool->SetNewValue( $k, $self->{meta}->{$k}, { AddValue => 0, IgnoreMinorErrors => 1, Verbose => 0 } );
				}
		my ( $out, $err ) = $ExifTool->WriteInfo( $self->{file}->{fullp}, $self->{file}->{newfullf}, { IgnoreMinorErrors => 1, Verbose => 0 } );
		return;
		}

sub dump_all($:$)    # Die erzeugte Begrüßung als String zurückgeben (z.&nbsp;B. Verwendung mit print()
{
		my $self    = shift @_;
		my $verbose = shift @_;

		#print Dumper \$self->{pdfinfo};
		#print Dumper \$self->{size};
		#delete( $self->{body} );
		#delete( $self->{header} );
		#delete( $self->{footer} );
		#delete( $self->{kopf} );
		#print Dumper \$self->{file}   if ($verbose);
		#print Dumper \$self->{pdftxt} if ($verbose);
		print Dumper \$self->{meta} if ($verbose);
		if ( $self->{meta}->{scan_understood} >= 50 ) {
				print "*** RES [ OK OK OK OK OK OK OK OK OK OK ] \n";
				print "*** TAG [ Deckbla ]: " . $self->{meta}->{cover_letter} . "\n";
				print "*** TAG [ DocTyp ]:  " . $self->{meta}->{match_type} . "\n";
				print "*** TAG [ DocClass ]:" . $self->{meta}->{match_class} . "\n";
				print "*** TAG [ Sender ]:  " . $self->{meta}->{sender} . "\n";
				print "*** TAG [ Subject ]: " . $self->{meta}->{subject} . "\n";
				print "*** TAG [ Title ]:   " . $self->{meta}->{Title} . "\n";
				print "*** TAG [ Datum ]:   " . $self->{meta}->{datum} . "\n";
				print "*** TAG [ Datum_0 ]:   " . $self->{meta}->{datum_0} . "\n";
				print "\n";
				print "*** TAG [ NewName ]: " . $self->{file}->{newfullf} . "\n";
				print "*** TAG [ unQuenam ]: " . $self->{file}->{donefullp} . "\n";

				#print "*** TAG [ Creator ]: " . $self->{meta}->{Creator} . "\n";
				#print "*** TAG [ Producer ]:" . $self->{meta}->{Producer} . "\n";
				#print "*** TAG [ Author ]:  " . $self->{meta}->{Author} . "\n";
				#print "*** TAG [ Keywords ]:" . $self->{meta}->{Keywords} . "\n";
				#print "*** TAG [ Date ]:    " . $self->{meta}->{datum} . "\n";
		} else {
				print "*** RES [ UNSURE UNSURE UNSURE ] \n";
				print "*** TAG [ Deckbla ]: " . $self->{meta}->{cover_letter} . "\n";
				print "*** TAG [ DocTyp ]:  " . $self->{meta}->{match_type} . "\n";
				print "*** TAG [ DocClass ]:" . $self->{meta}->{match_class} . "\n";
				print "*** TAG [ Sender ]:  " . $self->{meta}->{sender} . "\n";
				print "*** TAG [ Subject ]: " . $self->{meta}->{subject} . "\n";
				print "*** TAG [ Title ]:   " . $self->{meta}->{title} . "\n";
				print "*** TAG [ Datum ]:   " . $self->{meta}->{datum} . "\n";
				print "*** TAG [ NewName ]: " . $self->{file}->{newfullf} . "\n";
				print "*** TAG [ unQuenam ]: " . $self->{file}->{donefullp} . "\n";
				}
		return "Hello $self->{ding}!\n";
		}

sub mysubstr() {
		my $self = shift @_;
		my $str  = shift @_;
		my $pos  = shift @_;
		my $num  = shift @_;
		warn("### cut [$pos,$num] ($str)");
		$str =~ s/^([\p{L}\p{Nd} ]{1,50} ).*/$1/;
		warn("### to  [$pos,$num] ($str)");
		return $str;
		}

sub unqueue_pdf() {
		my $self = shift @_;
		warn("Result: $self->{file}->{newfullf}");
		exit 1 if (qx(mv $self->{file}->{fullp} $self->{file}->{donefullp}));
		}
return 1;    # Jedes Perl-Modul muss einen wahren Wert an den Compiler liefern, sonst gibt es einen Error
__DATA__

sub get_ocr($$$$$$$;$)    # Das Ding ändern, das begrüßt wird
{
		my $self    = shift @_;
		my $x       = shift @_;
		my $y       = shift @_;
		my $w       = shift @_;
		my $h       = shift @_;
		my $page    = shift @_;
		my $name    = shift @_;
		my $mycolor = shift @_;
		my $raw     = shift @_;
		my ( $package, $filename, $line ) = caller;
		$page = $self->{current_page} if ( $page == 0 );
		my $sth = $dbh->prepare( "select val from cache where filename='" . $self->{file}->{basen} . "' and name='" . $name . $raw . "'" );
		$sth->execute();
		my $result = $sth->fetchrow_hashref();
		return ( $result->{val} ) if ( !$self->{no_cache}->{ocr} && $result->{val} );
		warn("get_ocr with page 0 from $line") if ( $page == 0 );
		my $retval;
		my $cmd;
		$mycolor = 'red' if ( $mycolor eq "" );
		$mycolor = 'red' if ( $mycolor eq "" );
		return $self->{crop}->{cache}->{$name} if ( $self->{crop}->{cache}->{$name} );
		$self->{crop}->{mycolor}->{$name} = "red" if ( !$self->{crop}->{mycolor}->{$name} );
		$retval = undef;

		if ( $page < 0 ) {
				$page = 1;
				}
		if ( $y < 0 || $y > $self->{size}->{h}->{px} ) {
				$y = ( $self->{size}->{h}->{px} + $y );
				}
		if ( $x < 0 || $x > $self->{size}->{w}->{px} ) {
				$x = ( $self->{size}->{w}->{px} + $x );
				}
		if ( $h < 0 || $h > $self->{size}->{h}->{px} ) {
				$h = $self->{size}->{h}->{px} + $h;
				}
		if ( $w < 0 || $w > $self->{size}->{w}->{px} ) {
				$w = $self->{size}->{w}->{px} + $w;
				}
		$x    = floor($x);
		$y    = floor($y);
		$w    = floor($w);
		$h    = floor($h);
		$page = floor($page);
		if ( "$x$y$w$h$page" !~ m/^[\d\s]+$/ ) {
				warn("cropsize not ok: x:$x y:$y w:$w h:$h page:$page");
				return undef;
				}
		my $txtx = ( $x + $w ) / 10 * 8;
		my $txty = ( $y + $h ) - 10;
		my $ws   = $w - 1;
		my $hs   = $h - 1;
		if ( $raw eq "" ) {
				$raw = '-layout';
				if ( $self->{DOCROP} eq 1 ) {

						#print "**\n** $x,$y,$w,$h,$page,$name,$mycolor\n**\n";
						$cmd = "mogrify -region \"${ws}x${hs}+${x}+${y}\" -fill $mycolor -colorize 8% $self->{file}->{croppic}";
						qx($cmd);    # or warn($cmd);
						$cmd = "mogrify -fill none -stroke $mycolor -strokewidth 2  -draw \"rectangle $x, $y, ${ws}, ${hs}\"   $self->{file}->{croppic}";
						qx($cmd);    # or warn($cmd);

						#$cmd = "mogrify -density 40 -fill none -stroke $mycolor -draw \"text $txtx, $txty  '$name - $x x $y / $w x $h'\" $self->{file}->{croppic}";
						$cmd = "mogrify -density 50 -fill none -stroke $mycolor -draw \"text $txtx, $txty  '$name'\" $self->{file}->{croppic}";
						qx($cmd);    # or warn($cmd);
						}
				}
		$cmd = "pdftotext -q -enc UTF-8 -eol unix -nopgbrk $raw -r 72 -f $page -l $page -x $x -y $y -W $w -H $h '$self->{file}->{fullp}' -";

		#print STDERR "$cmd\n";
		$cmd                            = qx($cmd);
		$self->{crop}->{cache}->{$name} = $cmd;
		$sth                            = $dbh->prepare("REPLACE into cache (filename,name,val) values(?,?,?)");
		my $out = $self->{pdfinfo}->{raw} . $self->{pdfinfo}->{identify};
		$sth->execute( $self->{file}->{basen}, $name . $raw, $self->{crop}->{cache}->{$name} );
		return $self->{crop}->{cache}->{$name};
		}
