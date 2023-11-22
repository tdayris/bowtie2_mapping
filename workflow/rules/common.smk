import csv
import pandas
import snakemake
import snakemake.utils

from typing import Any, Dict, List, Optional, Union

snakemake.utils.min_version("7.29.0")

# containerized: "docker://snakemake/snakemake:v7.32.4"
# containerized: "docker://mambaorg/micromamba:git-8440cec-jammy-cuda-12.2.0"
# containerized: "docker://condaforge/mambaforge:23.3.1-1"


# Load and check configuration file
configfile: "config/config.yaml"


snakemake.utils.validate(config, "../schemas/config.schema.yaml")

# Load and check samples properties table
sample_table_path: str = config.get("samples", "config/samples.csv")
with open(sample_table_path, "r") as sample_table_stream:
    dialect: csv.Dialect = csv.Sniffer().sniff(sample_table_stream.read(1024))
    sample_table_stream.seek(0)

samples: pandas.DataFrame = pandas.read_csv(
    filepath_or_buffer=sample_table_path,
    sep=dialect.delimiter,
    header=0,
    index_col=None,
    comment="#",
    dtype=str,
)
snakemake.utils.validate(samples, "../schemas/samples.schema.yaml")

# This is here for compatibility with
genome_table_path: str = config.get("genomes")
if genome_table_path:
    with open(genome_table_path, "r") as genome_table_stream:
        dialect: csv.Dialect = csv.Sniffer().sniff(genome_table_stream.read(1024))
        genome_table_stream.seek(0)

    genomes: pandas.DataFrame = pandas.read_csv(
        filepath_or_buffer=genome_table_path,
        sep=dialect.delimiter,
        header=0,
        index_col=None,
        comment="#",
        dtype=str,
    )
else:
    genomes: pandas.DataFrame = samples[
        ["species", "build", "release"]
    ].drop_duplicates(keep="first", ignore_index=True)
    genomes.to_csv("genomes.csv", sep=",", index=False, header=True)
    config["genomes"] = "genomes.csv"

snakemake.utils.validate(genomes, "../schemas/genomes.schema.yaml")

snakemake_wrappers_version: str = "v2.13.0"

report: "../report/workflows.rst"

wildcard_constraints:
    sample=r"|".join(samples.sample_id),


def get_fastp_trimming_input(
    wildcards: snakemake.io.Wildcards,
    samples: pandas.DataFrame = samples,
    config: Dict[str, Any] = config,
) -> Dict[str, List[str]]:
    """
    Return expected input files for Bowtie2 mapping, according to user-input,
    and snakemake-wrapper requirements

    Parameters:
    wildcards (snakemake.io.Wildcards): Required for snakemake unpacking function
    samples   (pandas.DataFrame)      : Describe sample names and related paths/genome
    config    (Dict[str, Any])        : Configuration file

    Return (Dict[str, List[str]]):
    Dictionnary of all input files as required by Fastp's snakemake-wrapper
    """
    sample_data: Dict[str, str] = samples[
        samples.sample_id == str(wildcards.sample)
    ].to_dict(orient="index")[0]
    downstream_file = sample_data.get("downstream_file")
    if downstream_file:
        return {
            "sample": [sample_data["upstream_file"], downstream_file],
        }
    return {
        "sample": [sample_data["upstream_file"]],
    }


def get_bowtie2_alignment_input(
    wildcards: snakemake.io.Wildcards,
    samples: pandas.DataFrame = samples,
    config: Dict[str, Any] = config,
) -> Dict[str, Union[Dict[str, str], str]]:
    """
    Return expected input files for Bowtie2 mapping, according to user-input,
    and snakemake-wrapper requirements

    Parameters:
    wildcards (snakemake.io.Wildcards): Required for snakemake unpacking function
    samples   (pandas.DataFrame)      : Describe sample names and related paths/genome
    config    (Dict[str, Any])        : Configuration file

    Return (Dict[str, Union[Dict[str, str], str]]):
    Dictionnary of all input files as required by Bowtie2's snakemake-wrapper
    """
    sample_data: Dict[str, str] = samples[
        samples.sample_id == str(wildcards.sample)
    ].to_dict(orient="index")[0]
    species: str = str(sample_data["species"])
    build: str = str(sample_data["build"])
    release: str = str(sample_data["release"])
    datatype: str = "dna"

    idx: Optional[str] = config.get("resources", {}).get("bowtie2_index")
    if not idx:
        idx = multiext(
            f"reference/{species}.{build}.{release}.{datatype}",
            ".1.bt2",
            ".2.bt2",
            ".3.bt2",
            ".4.bt2",
            ".rev.1.bt2",
            ".rev.2.bt2",
        )

    results: Dict[str, List[str]] = {
        "idx": idx,
        "sample": [],
    }
    downstream_file: Optional[str] = sample_data.get("downstream_file")
    if downstream_file:
        results["sample"] = expand(
            "tmp/fastp/trimmed/{sample}.{stream}.fastq",
            stream=["1", "2"],
            sample=[str(wildcards.sample)],
        )
    else:
        results["sample"] = ["tmp/fastp/trimmed/{sample}.fastq"]

    return results


def get_multiqc_report_input(
    wildcards: snakemake.io.Wildcards, samples: pandas.DataFrame = samples
) -> Dict[str, List[str]]:
    """
    Return expected input files for MultiQC report, according to user-input,
    and snakemake-wrapper requirements

    Parameters:
    wildcards (snakemake.io.Wildcards): Required for snakemake unpacking function
    samples   (pandas.DataFrame)      : Describe sample names and related paths/genome

    Return (Dict[str, List[str]]):
    Dictionnary of all input files as required by MultiQC's snakemake-wrapper
    """
    results: Dict[str, List[str]] = {"picard_qc": [], "fastp": []}
    datatype: str = "dna"
    sample_iterator = zip(
        samples.sample_id,
        samples.species,
        samples.build,
        samples.release,
    )
    for sample, species, build, release in sample_iterator:
        results["picard_qc"] += multiext(
            f"tmp/picard/{species}.{build}.{release}.{datatype}/stats/{sample}",
            ".alignment_summary_metrics",
            ".insert_size_metrics",
            ".insert_size_histogram.pdf",
            ".base_distribution_by_cycle_metrics",
            ".base_distribution_by_cycle.pdf",
            ".gc_bias.detail_metrics",
            ".gc_bias.summary_metrics",
            ".gc_bias.pdf",
        )
        downstream_file: Optional[str] = (
            samples[samples.sample_id == sample]
            .to_dict(orient="index")[0]
            .get("downstream_file")
        )
        if downstream_file:
            results["fastp"].append(f"tmp/fastp/report_pe/{sample}.json")
            results["fastp"].append(f"tmp/fastp/report_pe/{sample}.html")
        else:
            results["fastp"].append(f"tmp/fastp/report_se/{sample}.json")
            results["fastp"].append(f"tmp/fastp/report_pe/{sample}.html")

    return results


def get_targets(
    wildcards: snakemake.io.Wildcards,
    samples: pandas.DataFrame = samples,
    config: Dict[str, Any] = config,
) -> Dict[str, List[str]]:
    """
    Return the expected list of output files at the end of the pipeline

    Parameters:
    wildcards (snakemake.io.Wildcards): Required for snakemake unpacking function
    samples   (pandas.DataFrame)      : Describe sample names and related paths/genome
    config    (Dict[str, Any])        : Configuration file

    Return (Dict[str, List(str)]):
    Dictionnary of expected output files
    """
    results: Dict[str, List[str]] = {
        "multiqc": [
            "results/QC/MultiQC.html",
            "results/QC/MultiQC_data.zip",
        ],
        "bams": [],
        "bais": [],
    }
    sample_iterator = zip(
        samples.sample_id,
        samples.species,
        samples.build,
        samples.release,
    )
    for sample, species, build, release in sample_iterator:
        results["bams"].append(
            f"results/Mapping/{species}.{build}.{release}.dna/{sample}.bam"
        )
        results["bais"].append(
            f"results/Mapping/{species}.{build}.{release}.dna/{sample}.bam.bai"
        )

    print(results)
    return results
