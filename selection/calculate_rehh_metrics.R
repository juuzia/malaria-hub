library(rehh)
library(dplyr)
library(data.table)
library(optparse)
library(ggplot2)
library(ggrepel)
library(stringr)

source("~/software/malaria-hub/selection/helpers.R")

option_list = list(
    make_option(c("-d", "--workdir"), type = "character", default = NULL,
              help = "Specify main directory", metavar = "character"),
    make_option(c("-p", "--prefix"), type = "character", default = "scanned_haplotypes",
              help = "Prefix", metavar = "character"),
    make_option(c("--list_category"), type = "character", default = NULL,
              help = "Category list", metavar = "character"),
    make_option(c("--annotation"), type = "character", default = NULL,
              help = "Annotation", metavar = "character"),
    make_option(c("--gene_product"), type = "character", default = NULL,
              help = "Gene product", metavar = "character"),
    make_option(c("--remove_chr"), type = "character", default = NULL,
              help = "Chromosomes to remove ex. Pf3D7_API_v3,Pf_M76611",
              metavar = "character"),
    make_option(c("--threads"), type = "integer", default = 4,
              help = "Specify threads [default %default]",
              metavar = "number")
);

opt_parser = OptionParser(option_list = option_list);
opt = parse_args(opt_parser);

# TODO as arg
setDTthreads(opt$threads)

# workdir
workdir <- opt$workdir
# prefix
prefix <-  opt$prefix
# list_category
category_list <- opt$list_category
# annotation
annotation_file <- opt$annotation
# gene_product
gene_product_file <- opt$gene_product
# Chromosomes to remove
rm_chr <- opt$remove_chr

# Pattern for chromosome detection
pattern <- "(.*?)_(.+)_(.*)"

# Y axis labels
ihs_expr <- expression("-" * log[10] * "[1" ~ "-" ~ "2" ~ "|" ~ Phi[scriptstyle(italic(iHS))] ~ "-" ~ 0.5 * "|]")
rbs_expr <- expression(-log[10] ~ "(" * italic(p) * "-value)")
xpehh_expr <- expression(-log[10] ~ "(" * italic(p) * "-value)")

# Load categories file
categories <- read.table(category_list, sep = "\n")$V1 %>% as.vector()

# Load annotation file Chr, Pos, Ref, Alt_1, Gene_name_1
annotation <- read.table(annotation_file, sep = "\t", fill = TRUE,
                         header = TRUE, stringsAsFactors = FALSE)
annotation <- annotation %>% select(c(Chr, Pos, Ref, Alt_1, Gene_name_1))

# Load gene/product file
gff_table <- read.csv(gene_product_file, sep = "\t",
                      header = TRUE, stringsAsFactors = FALSE) %>%
    as.data.frame()

# Filter chromosome from annotation and gene product table
if (!is.null(rm_chr)) {
  rm_chr <- strsplit(rm_chr, ",")[[1]]
  if (all(rm_chr %in% unique(annotation$Chr))) {
    annotation <- annotation %>% filter(!Chr %in% rm_chr)
    gff_table <- gff_table %>% filter(!chr %in% rm_chr)
  } else {
    stop("Wrong name for chromosomes to remove.")
  }
} else {
  message("None chromosomes removed")
}

# Transform chromosome names to numeric
annotation$Chr <- as.numeric(stringr::str_match(annotation$Chr, pattern)[, 3])
gff_table$chr <- as.numeric(stringr::str_match(gff_table$chr, pattern)[, 3])


high_ihs_all <- c()
cr_ihs_all <- c()

high_rbs_all <- c()
cr_rbs_all <- c()

high_xpehh_all <- c()
cr_xpehh_all <- c()

# Read IHH, IES, INES metrics and calculate iHS, rBS, XPEHH metric
# * Plot manhattan plot
# * Filter sites with high significance
# * Detect candidate regions
for (category in categories) {
  # Per category
  message(category, "\n")
  pdf(file.path(workdir, sprintf("plots_%s.pdf", category)))
  sink(file.path(workdir, paste0(category, "_metrics.log")))

  filec <- file.path(workdir, paste0(prefix, "_", category, ".tsv"))
  if (file.exists(filec)) {
    #### IHS #####
    cat("\n## iHS ##\n")
    ihh <- fread(filec, sep = "\t", header = TRUE, data.table = FALSE)
    ihs <- rehh::ihh2ihs(ihh, min_maf = 0.0, freqbin = 0.05)

    if (nrow(ihs$ihs) > 1) {
      ihsA <- ihs$ihs %>% left_join(annotation, by = c("CHR" = "Chr", "POSITION" = "Pos"))
      gg_data <- gg_to_plot <- modify_df_ggplot(ihsA, th = 4)

      generate_manhattan_ggplot(gg_data$df_vis, gg_data$df_axis,
                                th = 4,
                                name = sprintf("iHS: %s", gsub("_"," ", category)),
                                yname = ihs_expr,
                                hcolor = "lightblue")

      # Annotation
      high_ihs <- ihsA %>% filter(LOGPVALUE >= 4)
      if (nrow(high_ihs) > 1) {
        high_ihs$category_name <- category
        high_ihs_all <- rbind(high_ihs_all, high_ihs)
      }
      # Candidate regions
      cr_ihs <- rehh::calc_candidate_regions(ihs$ihs,
                                             threshold = 5,
                                             pval = TRUE,
                                             window_size = 2E4,
                                             overlap = 1E4,
                                             min_n_extr_mrk = 2)
      if (nrow(cr_ihs) > 1) {
        cr_ihs$category_name <- category
        cr_ihs_all <- rbind(cr_ihs_all, cr_ihs)
      }
    }

    # Pairwise comparisons
    if (length(categories >= 2)) {
      other_categories <- categories[-which(categories == category)]
      for (contr_category in other_categories) {
        cat(paste0("\n", contr_category, "\n"))

        fileoc <- file.path(workdir, paste0(prefix, "_", contr_category, ".tsv"))
        if (file.exists(fileoc)) {
          ihh_oc <- fread(fileoc, sep = "\t", header = TRUE, data.table = FALSE)
          #### RBS ####
          cat("\n## rBS ##\n")
          rbs <- rehh::ines2rsb(ihh, ihh_oc)

          if (nrow(rbs) > 1) {
            rbsA <- rbs %>% left_join(annotation, by = c("CHR" = "Chr", "POSITION" = "Pos"))
            gg_data <- gg_to_plot <- modify_df_ggplot(rbsA, th = 5)

            generate_manhattan_ggplot(gg_data$df_vis, gg_data$df_axis,
                                      th = 5,
                                      name = paste0("rBS: ", category, " vs ", contr_category),
                                      yname = rbs_expr,
                                      hcolor = "red")

            # High significance
            high_rbs <- rbsA %>% filter(LOGPVALUE >= 5)
            if (nrow(high_rbs) > 1) {
              high_rbs$category_name <- paste0(c(category, contr_category), collapse = "|")
              high_rbs_all <- rbind(high_rbs_all, high_rbs)
            }

            # Candidate regions
            cr_rbs <- rehh::calc_candidate_regions(rbs,
                                                   threshold = 5,
                                                   pval = TRUE,
                                                   window_size = 2E4,
                                                   overlap = 1E4,
                                                   min_n_extr_mrk = 2)
            if (nrow(cr_rbs) > 1) {
              cr_rbs$category_name <- paste0(c(category, contr_category), collapse = "|")
              cr_rbs_all <- rbind(cr_rbs_all, cr_rbs)
            }
          }

          #### XPEHH #####
          cat("\n## XPEHH ##\n")
          xpehh <- rehh::ies2xpehh(ihh, ihh_oc)

          if (nrow(xpehh) > 1) {
            xpehhA <- xpehh %>% left_join(annotation, by = c("CHR" = "Chr", "POSITION" = "Pos"))
            gg_data <- gg_to_plot <- modify_df_ggplot(xpehhA, th = 5)

            generate_manhattan_ggplot(gg_data$df_vis, gg_data$df_axis,
                            th = 5,
                            name = paste0("XPEHH: ", category, " vs ", contr_category),
                            yname = xpehh_expr,
                            hcolor = "purple")

            high_xpehh <- xpehhA %>% filter(LOGPVALUE >= 5)
            if (nrow(high_xpehh) > 1) {
              high_xpehh$category_name <- paste0(c(category, contr_category), collapse = "|")
              high_xpehh_all <- rbind(high_xpehh_all, high_xpehh)
            }

            cr_xpehh <- rehh::calc_candidate_regions(xpehh,
                                                     threshold = 5,
                                                     pval = TRUE,
                                                     window_size = 2E4,
                                                     overlap = 1E4,
                                                     min_n_extr_mrk = 2)
            if (nrow(cr_xpehh) > 1) {
              cr_xpehh$category_name <- paste0(c(category, contr_category), collapse = "|")
              cr_xpehh_all <- rbind(cr_xpehh_all, cr_xpehh)
            }
          }
        }
      }
    } else {
      message('Only iHS results calculated. Not enough populations for rBS, XPEHH.')
    }
  }
  sink()
  dev.off()
}

# Save iHs, rBS, XP-EHH results for all categories
# iHS
if (length(high_ihs_all) != 0) {
  write.table(high_ihs_all, file.path(workdir, "high_ihs_all_categories.tsv"),
  quote = FALSE, row.names = FALSE, col.names = TRUE, sep = "\t")
}
 
if (length(cr_ihs_all) != 0) {
  cr_ihs_ann <- annotate_candidate_regions(cr_ihs_all, gff_table)
  write.table(cr_ihs_ann, file.path(workdir, "cr_ihs_all_categories_annot.tsv"),
  quote = FALSE, row.names = FALSE, col.names = TRUE, sep = "\t")
}

# rBS
if (length(high_rbs_all) != 0) {
  write.table(high_rbs_all, file.path(workdir, "high_rbs_all_categories.tsv"),
  quote = FALSE, row.names = FALSE, col.names = TRUE, sep = "\t")
}
if (length(cr_rbs_all) != 0) {
  cr_rbs_ann <- annotate_candidate_regions(cr_rbs_all, gff_table)
  write.table(cr_rbs_ann, file.path(workdir, "cr_rbs_all_categories_annot.tsv"),
  quote = FALSE, row.names = FALSE, col.names = TRUE, sep = "\t")
}

# XPEHH
if (length(high_xpehh_all) != 0) {
  write.table(high_xpehh_all, file.path(workdir, "high_xpehh_all_categories.tsv"),
  quote = FALSE, row.names = FALSE, col.names = TRUE, sep = "\t")
}

if (length(cr_xpehh_all) != 0) {
  cr_xpehh_ann <- annotate_candidate_regions(cr_xpehh_all, gff_table)
  write.table(cr_xpehh_ann, file.path(workdir, "cr_xpehh_all_categories_annot.tsv"),
  quote = FALSE, row.names = FALSE, col.names = TRUE, sep = "\t")
}