package MicrobiomeWorkflow::Main::WorkflowSteps::DecorateEukdetectResultsWithTaxa;

@ISA = (ApiCommonWorkflow::Main::WorkflowSteps::WorkflowStep);

use strict;
use warnings;
use ApiCommonWorkflow::Main::WorkflowSteps::WorkflowStep;
use List::Util qw/reduce/;
use feature 'say';

sub run {
  my ($self, $test, $undo) = @_;
  my $inputPath = join("/", $self->getWorkflowDataDir(),  $self->getParamValue("inputPath"));
  my $outputPath = join("/", $self->getWorkflowDataDir(),  $self->getParamValue("outputPath"));

  if($undo){
    return;
  }
  if($test){
    die "No file at $inputPath" unless -f $inputPath;
    `touch $outputPath`;
    return;
  }
  $self->decorateFile($inputPath, $outputPath);
}
sub getLineageFromSubstring {
  my ($self, $x) = @_;
  my ($ncbiTaxonId) = $x =~ m{^(\d+)};
  die "No taxon id in $x" unless $ncbiTaxonId;
  my @lineage = $self->getMbioLineageForTaxonId($ncbiTaxonId);
  die "No lineage found for taxon $ncbiTaxonId" unless @lineage;
  return @lineage;
}

sub getJoinedLineageFromSubstrings {
  my ($self, @xs) = @_;
  my %ls;
  for my $x (@xs){
    my @lineage = $self->getLineageFromSubstring($x);
    die $x unless @lineage == 7;
    for my $n (0..6){
      $ls{$n}{$lineage[$n]}++;
    }
  }
  my @lineage;
  for my $n (0..6){
    my ($k, @ks) = keys %{$ls{$n}};
    if ($k and not @ks and $n < 6){
      push @lineage, $k;
    } else {
      push @lineage, "";
    }
  }
  return @lineage;
}

sub getLineageFromId {
  my ($self, $id) = @_;
  if ($id =~ m{^\?}){
    $id =~ s{^\?}{};
    return $self->getJoinedLineageFromSubstrings(split(",", $id));
  } else {
    return $self->getLineageFromSubstring($id);
  }
}
sub decorateFile {
  my ($self, $inputPath, $outputPath) = @_;
  my $header;

  my %result;

  open(my $fh, "<", $inputPath) or die "$!: $inputPath";
  my ($idH, $valuesH) = split("\t", <$fh>, 2);
  chomp $valuesH;
  $header = "lineage\t$valuesH";
  my $dim;
  while(my ($id, $values) = split ("\t", <$fh>, 2)){
    my @lineage = $self->getLineageFromId($id);
    chomp $values;
    my @vs = split("\t", $values, -1);
    if($dim and scalar @vs != $dim){
      die "Inconsistent num values in line $.";
    }
    $dim = @vs;

    my $k = join(";", @lineage);
    push @{$result{$k}}, \@vs;
  }

  open(my $outfh, ">", $outputPath) or die "$!: $outputPath";
  say $outfh $header;
  for my $k (sort keys %result){
    my $vs = reduce { my @pairwiseSum = map {my $x = ($a->[$_] ||0) + ($b->[$_]||0); $x || ""} 0..($dim-1) ; \@pairwiseSum } @{$result{$k}};
    say $outfh join "\t", $k, @$vs;
  }
}

my $levelsString = "'superkingdom', 'clade', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species'";

# We try to use old kingdoms in top level if possible: plants / animals / fungi
sub topLevel {
  my ($result) = @_;
  if ($result->{superkingdom} eq 'Bacteria'){
    return 'Bacteria';
  } elsif ($result->{superkingdom} eq 'Archaea'){
    return 'Archaea';
  } else {
    return $result->{kingdom} // $result->{clade} // $result->{superkingdom};
  }
}
sub getMbioLineageForTaxonId {
  my ($self, $ncbiTaxonId) = @_;
  my $sql = "
select rank, name from (
select taxon_id, ncbi_tax_id, rank from sres.taxon
   connect by taxon_id = prior parent_id
   start with ncbi_tax_id = $ncbiTaxonId
) t, sres.taxonname tn
where t.taxon_id = tn.taxon_id
and name_class = 'scientific name'
and rank in ($levelsString)
";

  my %result;
  my $stmt = $self->getWorkflow()->_runSql($sql);
  while (my ($rank, $name) = $stmt->fetchrow_array()) {
    $result{$rank} = $name;
  }
  return unless %result;
  return map {$_ // ""} (topLevel(\%result), @result{('phylum', 'class', 'order', 'family', 'genus', 'species')});
}

