package MicrobiomeWorkflow::Main::WorkflowSteps::MakeEukdetectNextflowConfig;

@ISA = (ApiCommonWorkflow::Main::WorkflowSteps::WorkflowStep);

use strict;
use warnings;
use ApiCommonWorkflow::Main::WorkflowSteps::WorkflowStep;

sub run {
  my ($self, $test, $undo) = @_;

  my $configPath = join("/", $self->getWorkflowDataDir(),  $self->getParamValue("analysisDir"), $self->getParamValue("configFileName"));
  my $sampleToFastqPath = join("/", $self->getWorkflowDataDir(), $self->getParamValue("analysisDir"), $self->getParamValue("sampleToFastqFileName"));
  my $clusterSampleToFastqPath = join("/", $self->getClusterWorkflowDataDir(), $self->getParamValue("analysisDir"), $self->getParamValue("sampleToFastqFileName"));
  my $eukdetectRefdbPath= join("/", $self->getClusterWorkflowDataDir(), $self->getParamValue("eukdetectRefdbPath"));
  my $eukdetectMarkerToTaxonPath= join("/", $self->getClusterWorkflowDataDir(), $self->getParamValue("eukdetectMarkerToTaxonPath"));
  my $clusterResultDir = join("/", $self->getClusterWorkflowDataDir(), $self->getParamValue("clusterResultDir"));

  my $libraryLayout = $self->getParamValue("isPaired") ? "paired" : "single";
  my $downloadMethod = $self->getParamValue("downloadMethod");
  my $unpackMethod = $self->getParamValue("unpackMethod");

  my $executor = $self->getClusterExecutor();
  my $queue = $self->getClusterQueue();

  if ($undo) {
    $self->runCmd(0,"rm -rf $configPath");
  } else {
    $self->testInputFile('sampleToFastqPath', $sampleToFastqPath);

    open(F, ">", $configPath) or die "$! :Can't open config file '$configPath' for writing";

    # limited downloads in parallel make the pipeline start slow
    # 'finish' on align jobs make it wind down gracefully on error to not waste compute
    print F
"
params {
  inputPath = '$clusterSampleToFastqPath'
  resultDir = '$clusterResultDir'
  libraryLayout = '$libraryLayout'
  downloadMethod = '$downloadMethod'
  unpackMethod = '$unpackMethod'
  refdb = '$eukdetectRefdbPath'
  markerToTaxonPath = '$eukdetectMarkerToTaxonPath'
  summarizeAlignmentsCommand = 'marker_alignments --min-read-query-length 60 --min-taxon-num-markers 2 --min-taxon-num-reads 2 --min-taxon-better-marker-cluster-averages-ratio 1.01 --threshold-avg-match-identity-to-call-known-taxon 0.95  --threshold-num-taxa-to-call-unknown-taxon 1 --threshold-num-markers-to-call-unknown-taxon 4     --threshold-num-reads-to-call-unknown-taxon 4'

}

process {
  executor = '$executor'
  queue = '$queue'
  maxForks = 60

  withLabel: 'download' {
    errorStrategy = 'retry'
    maxForks = 5
    maxRetries = 3
  }
  withLabel: 'align' {
    errorStrategy = 'finish'
  }
}
";
  close(F);
 }
}

1;

