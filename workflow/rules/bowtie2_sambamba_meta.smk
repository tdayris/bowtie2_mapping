module bowtie2_sambamba:
    meta_wrapper:
        f"{snakemake_wrappers_version}/meta/bio/bowtie2_sambamba"


use rule bowtie2_build from bowtie2_sambamba with:
    input:
        "reference/{species}.{build}.{release}.{datatype}.fasta",
    output:
        multiext(
            "reference/{species}.{build}.{release}.{datatype}",
            ".1.bt2",
            ".2.bt2",
            ".3.bt2",
            ".4.bt2",
            ".rev.1.bt2",
            ".rev.2.bt2",
        ),
    cache: True
    log:
        "logs/bowtie2/build/{species}.{build}.{release}.{datatype}.log",
    benchmark:
        "benchmark/bowtie2/build/{species}.{build}.{release}.{datatype}.tsv"
    params:
        extra=config.get("params", {}).get("bowtie2", {}).get("build", ""),


use rule bowtie2_alignment from bowtie2_sambamba with:
    input:
        unpack(get_bowtie2_alignment_input),
    output:
        temp("results/bowtie2/{species}.{build}.{release}.{datatype}/{sample}_raw.bam"),
    log:
        "logs/bowtie2/align/{species}.{build}.{release}.{datatype}/{sample}.log",
    benchmark:
        "benchmark/bowtie2/align/{species}.{build}.{release}.{datatype}/{sample}.tsv"
    params:
        extra=config.get("params", {})
        .get("bowtie2", {})
        .get(
            "align",
            " --rg-id {sample} --rg 'SM:{sample} LB:{sample} PU:{species}.{build}.{release}.{datatype}.{sample} PL:ILLUMINA'",
        ),


use rule sambamba_sort from bowtie2_sambamba with:
    input:
        "results/bowtie2/{species}.{build}.{release}.{datatype}/{sample}_raw.bam",
    output:
        temp("sambamba/sort/{species}.{build}.{release}.{datatype}/{sample}.bam"),
    log:
        "logs/sambamba/sort/{species}.{build}.{release}.{datatype}/{sample}.log",
    benchmark:
        "benchmark/sambamba/sort/{species}.{build}.{release}.{datatype}/{sample}.tsv"


use rule sambamba_view from bowtie2_sambamba with:
    input:
        "results/sambamba/sort/{species}.{build}.{release}.{datatype}/{sample}.bam",
    output:
        temp("sambamba/view/{species}.{build}.{release}.{datatype}/{sample}.bam"),
    log:
        "logs/sambamba/view/{species}.{build}.{release}.{datatype}/{sample}.log",
    benchmark:
        "benchmark/sambamba/view/{species}.{build}.{release}.{datatype}/{sample}.tsv"
    params:
        extra=config.get("params", {})
        .get("sambamba", {})
        .get(
            "view",
            "--format 'bam' --filter 'mapping_quality >= 30 and not (unmapped or mate_is_unmapped)'",
        ),


use rule sambamba_markdup from bowtie2_sambamba with:
    input:
        "results/sambamba/view/{species}.{build}.{release}.{datatype}/{sample}.bam",
    output:
        "results/Mapping/{species}.{build}.{release}.{datatype}/{sample}.bam",
    log:
        "logs/sambamba/markdup/{species}.{build}.{release}.{datatype}/{sample}.log",
    benchmark:
        "benchmark/sambamba/markdup/{species}.{build}.{release}.{datatype}/{sample}.tsv"
    params:
        extra=config.get("params", {})
        .get("sambamba", {})
        .get("markdup", "--remove-duplicates"),


use rule sambamba_index from bowtie2_sambamba with:
    input:
        "results/sambamba/markdup/{species}.{build}.{release}.{datatype}/{sample}.bam",
    output:
        "results/Mapping/{species}.{build}.{release}.{datatype}/{sample}.bam.bai",
    log:
        "logs/sambamba/index/{species}.{build}.{release}.{datatype}/{sample}.log",
    benchmark:
        "benchmark/sambamba/index/{species}.{build}.{release}.{datatype}/{sample}.tsv"
