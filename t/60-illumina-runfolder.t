use strict;
use warnings;
use Test::More tests => 43;
use Test::Exception;
use Carp;
use Archive::Tar;
use IO::File;
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile rel2abs catdir);
use Cwd;

use t::dbic_util;

use_ok('npg_tracking::illumina::runfolder');

my $CLEANUP=1;

my $testrundata = catfile(rel2abs(dirname(__FILE__)),q(data),q(090414_IL24_2726.tar.bz2));

my $origdir = getcwd;
my $testdir = catfile(tempdir( CLEANUP => $CLEANUP ), q()); #we need a trailing slash after our directory for the globbing later
chdir $testdir or croak "Cannot change to temporary directory $testdir";
diag ("Extracting $testrundata to $testdir");
system('tar','xjf',$testrundata) == 0 or Archive::Tar->extract_archive($testrundata, 1);
chdir $origdir; #so cleanup of testdir can go ahead
my $testrundir = catdir($testdir,q(090414_IL24_2726));

{
  my $rf;

  lives_ok {
    $rf = npg_tracking::illumina::runfolder->new( runfolder_path => $testrundir);
  } 'runfolder from valid runfolder_path';
  { my $id_run;
    lives_ok { $id_run = $rf->id_run; } 'id_run parsed';
    is($id_run, 2726, 'id_run correct');
  }
  { my $name;
    lives_ok { $name = $rf->name; } 'name parsed';
    is($name, q(IL24_2726), 'name correct');
  }
  { my $is_rta;
    lives_ok { $is_rta = $rf->is_rta; } 'check is_rta';
    ok(!$is_rta, 'not RTA run');
  }

  mkdir catdir($testrundir,qw(Data));
  mkdir catdir($testrundir,qw(Data Intensities));
  { my $is_rta;
    $rf = npg_tracking::illumina::runfolder->new( runfolder_path => $testrundir);
    lives_ok { $is_rta = $rf->is_rta; } 'check is_rta';
    ok($is_rta, 'RTA run - when Intensities directory added');
  }
  {  my $name;
    lives_ok {
      $rf = npg_tracking::illumina::runfolder->new(_folder_path_glob_pattern=>$testdir, id_run=> 2726, npg_tracking_schema => undef);
      $name = $rf->name;
    } 'runfolder from valid id_run';
    is($name, q(IL24_2726), 'name parsed');
  }
  my $rfpath =  catdir($testdir,q(090414_IL99_2726));
  mkdir $rfpath;
  throws_ok {
    $rf = npg_tracking::illumina::runfolder->new(_folder_path_glob_pattern=>$testdir, id_run=> 2726, npg_tracking_schema => undef);
    $rf->runfolder_path;
  } qr/Ambiguous paths/, 'throws when ambiguous run folders found for id_run';
  rmdir catdir($testdir,q(090414_IL99_2726));
  symlink $testrundir, catdir($testdir,q(superfoo_r2726));
  lives_ok {
    $rf = npg_tracking::illumina::runfolder->new(_folder_path_glob_pattern=>$testdir, id_run=> 2726, npg_tracking_schema => undef);
    $rf->runfolder_path;
  } 'lives when ambiguous run folders found for id_run but they correspond, via links or such, to the same folder';
  unlink catdir($testdir,q(superfoo_r2726));
  throws_ok {
    $rf = npg_tracking::illumina::runfolder->new(_folder_path_glob_pattern=>$testdir, id_run=> 2, npg_tracking_schema => undef);
    $rf->run_folder;
  } qr/No path/, 'throws when no run folders found for id_run';
  my $path;
  lives_ok {
    $rf = npg_tracking::illumina::runfolder->new(_folder_path_glob_pattern=>$testdir, name=> q(IL24_2726), npg_tracking_schema => undef);
    $path = $rf->runfolder_path;
  } 'runfolder from valid name';
  is($path, catdir($testdir,q(090414_IL24_2726)), 'runfolder path found');
  IO::File->new(catfile($testrundir,q(Recipe_foo.xml)), q(w));
  throws_ok {
    $rf->expected_cycle_count;
  } qr/Multiple recipe files found:/, 'throws when multiple recipes found';
  unlink catfile($testrundir,q(Recipe_foo.xml));
  my $expected_cycle_count;
  my (@read_cycle_counts, @indexing_cycle_range, @read1_cycle_range, @read2_cycle_range);
  lives_ok {
    $expected_cycle_count = $rf->expected_cycle_count;
    @read_cycle_counts = $rf->read_cycle_counts;
    @indexing_cycle_range = $rf->indexing_cycle_range;
    @read1_cycle_range = $rf->read1_cycle_range;
    @read2_cycle_range = $rf->read2_cycle_range;
  } 'finds and parses recipe file';
  is($expected_cycle_count,61,'expected_cycle_count');
  is_deeply(\@read_cycle_counts,[54,7],'read_cycle_counts');
  is_deeply(\@read1_cycle_range,[1,54],'read1_cycle_range');
  is_deeply(\@indexing_cycle_range,[55,61],'indexing_cycle_range');
  is_deeply(\@read2_cycle_range,[],'read2_cycle_range');
  my $lane_count;
  lives_ok {
    $rf = npg_tracking::illumina::runfolder->new(_folder_path_glob_pattern=>$testdir, name=> q(090414_IL24_2726), npg_tracking_schema => undef);
    $lane_count = $rf->lane_count;
  } 'finds and parses recipe file';
  is($lane_count,8,'lane_count');
  rename catfile($testrundir,q(Config),q(TileLayout.xml)), catfile($testrundir,q(Config),q(gibber_TileLayout.xml));
  throws_ok {
    $rf->tile_count;
  } qr/Can't open/, 'throws on no TileLayout.xml';
  rename catfile($testrundir,q(Config),q(gibber_TileLayout.xml)), catfile($testrundir,q(Config),q(TileLayout.xml));
  my $tile_count;
  lives_ok {
    $tile_count = $rf->tile_count;
  } 'loads tilelayout file';
  is($tile_count,100,'tile_count');
}

{
  my $test_runfolder_path;
  lives_ok {
    $test_runfolder_path = npg_tracking::illumina::runfolder->new(
      runfolder_path=> $testrundir, npg_tracking_schema => undef);
  } 'runfolder from valid runfolder_path';
  is($test_runfolder_path->run_folder(), '090414_IL24_2726',
    q{run folder obtained ok when runfolder_path used in construction});
}

{
  my $new_name = q(4567XXTT98);
  my $testrundir_new = catdir($testdir, $new_name);
  rename $testrundir, $testrundir_new;
  my $schema = t::dbic_util->new->test_schema();
  my $id_run = 33333;
  my $data = {
    actual_cycle_count   => 30,
    batch_id             => 939,
    expected_cycle_count => 37,
    id_instrument        => 3,
    id_run               => $id_run,
    id_run_pair          => 0,
    team                 => 'RAD',
    is_paired            => 0,
    priority             => 1,
    flowcell_id          => 'someid', 
    id_instrument_format => 1,
    folder_name          => $new_name,
    folder_path_glob     => $testdir
  };
  
  my $run_row = $schema->resultset('Run')->create($data);
  $run_row->set_tag(1, 'staging');

  my $rf;

  $rf = npg_tracking::illumina::runfolder->new(
    id_run              => 33333, 
    npg_tracking_schema => undef);
  throws_ok { $rf->run_folder } qr/No paths to run folder found/,
   'error - not able to find a runfolder without db help';
  throws_ok { $rf->runfolder_path } qr/No paths to run folder found/,
   'error - not able to find a runfolder without db help';

  $rf = npg_tracking::illumina::runfolder->new(
      id_run              => 33333, 
      npg_tracking_schema => $schema);
  is ($rf->run_folder, $new_name, 'runfolder name with db helper');
  is ($rf->runfolder_path,  $testrundir_new, 'runfolder path with db helper');

  $rf = npg_tracking::illumina::runfolder->new(
    run_folder          => $new_name,  
    npg_tracking_schema => undef);
  throws_ok { $rf->id_run } qr/Attribute \(id_run\) does not pass the type constraint/,
    'error - not able to infer run id without db help';
  throws_ok { $rf->runfolder_path } qr/No paths to run folder found/,
    'error - not able to find a runfolder without db help';

  $rf = npg_tracking::illumina::runfolder->new(
      run_folder          => $new_name, 
      npg_tracking_schema => $schema);
  is ($rf->id_run, 33333, 'id_run with db helper');
  is ($rf->runfolder_path,  $testrundir_new, 'runfolder path with db helper');

  $rf = npg_tracking::illumina::runfolder->new(
    runfolder_path      => $testrundir_new,
    npg_tracking_schema => undef);
  throws_ok { $rf->id_run } qr/Attribute \(id_run\) does not pass the type constraint/,
    'error - not able to infer run id without db help';
  is ($rf->run_folder, $new_name, 'runfolder name without db help');

  $rf = npg_tracking::illumina::runfolder->new(
      runfolder_path      => $testrundir_new, 
      npg_tracking_schema => $schema);
  is ($rf->id_run, 33333, 'id_run with db helper');
  is ($rf->run_folder, $new_name, 'runfolder with db helper');

  rename $testrundir_new, $testrundir; 
}

1;