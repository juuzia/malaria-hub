## Script to hold helper functions for selection scripts
## prepare_input_rehh_per_category.R
## calculate_rehh_metrics.R

# Count reference snp
ref <- function(x) {sum(1 * (as.numeric(x) == 0), na.rm = TRUE)}
# Count alternative snp
alt <- function(x) {sum(1 * (as.numeric(x) == 1), na.rm = TRUE)}

# Calculate MAF frequency for bi-allelic snps
calculate_maf <- function(x) {
  cref <- apply(x, 1, ref)
  calt <- apply(x, 1, alt)
  af <- calt / (calt + cref)
  maf <- ifelse(af > 0.5, 1 - af, af)
}

# Modify rehh table to fit qqman:manhattan() input requirements
modify_df_qqman <- function(df) {
  dfsel <- df %>% mutate(CHR = as.numeric(CHR),
                        BP = as.numeric(POSITION),
                        P = as.numeric(LOGPVALUE))
}


# Generate simple manhattan plot with qqman package
manhattan_plot <- function(df, title, yname, colors = NULL) {
    if (is.null(colors)) {
      colors <- c("black", "grey")
    }
    ymax <- ceiling(max(df$P, na.rm = TRUE))
    manhattan(df,
              logp = FALSE,
              main = title,
              genomewideline = 5,
              suggestiveline = 20,
              ylab = yname,
              col = colors,
              ylim = c(0, ymax))
}

# Modify rehh table for ggplot manhattan visualization
modify_df_ggplot <- function(df, th=4) {
  # Add highlight for snps with P > th
  # Add label for genes with at least 2 significant snps
  df <- df %>% 
    select(CHR, POSITION, LOGPVALUE, Alt_1, Gene_name_1) %>%
    mutate(CHR = as.numeric(CHR),
          POSITION = as.numeric(POSITION),
          LOGPVALUE = as.numeric(LOGPVALUE)) %>%
    filter(!is.na(LOGPVALUE)) %>%
    group_by(Gene_name_1) %>%
    mutate(pc = sum(LOGPVALUE >= th)) %>%
    ungroup() %>%
    mutate(is_annotate = ifelse(Gene_name_1 != "" & pc >= 2, "yes", "no"),
           is_highlight = ifelse(LOGPVALUE >= th, "yes", "no"))
          
  # Compute chromosome sizes
  mod_df <- df %>%
  group_by(CHR) %>%
  summarise(chr_len = max(POSITION), .groups = "drop") %>%
  # Calculate cumulative position of each chromosome
  mutate(tot = cumsum(chr_len) - chr_len) %>%
  select(-chr_len) %>%
  # Add this info to the initial dataset
  left_join(df, ., by = c("CHR" = "CHR")) %>%
  # Add a cumulative position of each SNP
  arrange(CHR, POSITION) %>%
  mutate(BPcum = POSITION + tot) %>%
  ungroup()

  axis_df <- mod_df %>%
   group_by(CHR) %>%
   summarize(center = (max(BPcum) + min(BPcum)) / 2)

  list("df_vis" = mod_df, "df_axis" = axis_df)
}

# Generate manhattan plot for iHS, rBS, XPEHH results
generate_manhattan_ggplot <- function(df, axis, th, name, yname, hcolor = "orange") {

  p <- ggplot(data = df, aes(x = BPcum, y = LOGPVALUE)) +
      geom_point(aes(color = as.factor(CHR)), alpha = 1, size = 1.3) +
      scale_color_manual(values = rep(c("black", "grey"), 22)) +
      scale_x_continuous(label = axis$CHR, breaks = axis$center) +
      geom_point(data = subset(df, is_highlight == "yes"),
                 color = hcolor, size = 1.5) +
      geom_label_repel(data = (df %>% filter(is_annotate == "yes") %>%
                       group_by(Gene_name_1) %>% top_n(1, LOGPVALUE)),
                       aes(label = Gene_name_1), size = 2) +
      geom_hline(yintercept = th, color = "red", alpha = 0.8) +
      labs(title = name,
           x = "Chromosomes",
           y = yname) +
      theme_bw() +
      theme(
          legend.position = "none",
          panel.border = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank()
      )
    print(p)
}

# Annotate genomic regions
annotate_candidate_regions <- function(cr_res, annot) {
  # Creating overlap to identify genes in candidate regions
  x <- data.table(chr = as.numeric(annot$chr),
                  start = as.numeric(as.character(annot$pos_start)),
                  end = as.numeric(as.character(annot$pos_end)))
  y <- data.table(chr = as.numeric(as.character(cr_res$CHR)),
                  start = as.numeric(as.character(cr_res$START)),
                  end = as.numeric(as.character(cr_res$END)))
  
  data.table::setkey(y, chr, start, end)
  overlaps <- data.table::foverlaps(x, y, type = "any", which = TRUE)

  cr_res <- cr_res %>% 
      arrange(CHR, START, END) %>%
      mutate(idR = row_number())
  annot <- annot %>% dplyr::mutate(idA = row_number())
  df_overlaps <- as.data.frame(overlaps)

  # Merging
  res_annot <- cr_res %>%
    left_join(df_overlaps, by = c("idR" = "yid")) %>%
    left_join(annot, by = c("xid" = "idA"))
  res_annot <- res_annot %>% dplyr::select(-c("idR", "xid", "chr"))

  return(res_annot)
}