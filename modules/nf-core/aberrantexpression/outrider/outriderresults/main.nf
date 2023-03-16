process RESULTS {
//    tag "$meta.id"
    label 'process_low'


    conda (params.enable_conda ? "bioconductor-outrider:1.16.0--r42hc247a5b_0" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'quay.io/biocontainers/drop:1.2.4--pyhdfd78af_0':
        'quay.io/biocontainers/drop:1.2.4--pyhdfd78af_0' }"

    input:
        each path(ods)
        val add_HPO_cols
        path(geneAnnotation)
        val(padjCutoff)
        val(zScoreCutoff)

    output:
        path("results_all.Rds")       , emit: results_all
        path("results.tsv")           , emit: results_tsv
        path "versions.yml"           , emit: versions

    shell:
    '''
    #!/usr/bin/env Rscript --vanilla

    source("!{add_HPO_cols}")

    suppressPackageStartupMessages({
        library(dplyr)
        library(data.table)
        library(ggplot2)
        library(SummarizedExperiment)
        library(OUTRIDER)
    })

    ods <- readRDS("!{ods}")
    res <- results(ods, padjCutoff = !{padjCutoff},
                zScoreCutoff = !{zScoreCutoff}, all = TRUE)

    # Add fold change
    res[, foldChange := round(2^l2fc, 2)]

    # Save all the results and significant ones
    saveRDS(res, "results_all.Rds")

    # Subset to significant results
    res <- res[padjust <= !{padjCutoff} &
                abs(zScore) > !{zScoreCutoff}]

    gene_annot_dt <- fread("!{geneAnnotation}")
    if(!is.null(gene_annot_dt$gene_name)){
    if(grepl('ENSG00', res[1,geneID]) & grepl('ENSG00', gene_annot_dt[1,gene_id])){
        res <- merge(res, gene_annot_dt[, .(gene_id, gene_name)],
                    by.x = 'geneID', by.y = 'gene_id', sort = FALSE, all.x = TRUE)
        setnames(res, 'gene_name', 'hgncSymbol')
        res <- cbind(res[, .(hgncSymbol)], res[, - 'hgncSymbol'])
    }
    }

    # Add HPO terms, requires online connection and for there to be annotated HPO terms
    sa <- fread("!{geneAnnotation}",
                colClasses = c(RNA_ID = 'character', DNA_ID = 'character'))
    if(!is.null(sa$HPO_TERMS) & nrow(res) > 0){
    if(!all(is.na(sa$HPO_TERMS)) & ! all(sa$HPO_TERMS == '')){
        res <- add_HPO_cols(res, hpo_file = "!{add_HPO_cols}")
    }
    }


    # Save results
    fwrite(res, "results.tsv", sep = "\t", quote = F)

    # run the version part
    cat(file="versions.yml", "!{task.process}:\naberrantexpression: 1.3.0")
    '''
}
