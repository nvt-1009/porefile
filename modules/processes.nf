
process gunzip {
	label 'small_cpus'
	label 'small_mem'

	input:
	file "*"

	output:
	file "*"

	script:
	"""
	gunzip -f *.gz
	"""
}


process downloadFasta {
	label 'internet'
	label 'small_cpus'
	label 'small_mem'

	output:
	path("*.fasta")

	script:
	"""
	wget ${params.silvaFastaURL}
	gunzip *gz
	"""
}

process downloadAccTaxID {
	label 'internet'
	label 'small_cpus'
	label 'small_mem'

	output:
	path("*acc_taxid")

	script:
	"""
	wget ${params.silvaAccTaxIDURL}
	gunzip *gz
	"""
}


process trimAccTaxID {
	label 'small_cpus'
	label 'small_mem'

	input:
	file "tax_slv_ssu_138.acc_taxid"


	output:
	path("SSURef_Nr99_tax_silva_to_NCBI_synonyms.map")


	script:
	"""
	cat tax_slv_ssu_138.acc_taxid | awk -F '[.\\t]' '{print \$1 "\\t" \$4}' > SSURef_Nr99_tax_silva_to_NCBI_synonyms.map
	"""
}

process Concatenate {
	label "small_cpus"
	label "small_mem"

	input:
	file "*fastq"

	output:
	file "allfq.fastq"

	script:
	"""
	cat *fastq > allfq.fastq
	"""
}


process Demultiplex {
	label "big_cpus"
	label "big_mem"
	scratch true

	input:
	file fq

	output:
	file "porechop_results/*"

	shell:
	"""
	porechop -t ${task.cpus} -i ${fq} -b porechop_results
	rm -f porechop_results/none.fastq
	"""
}

process Filter {
	tag "$barcode_id"
	label "small_cpus"

	input:
	tuple val(barcode_id), file("${barcode_id}.fastq")

	output:
	tuple val(barcode_id), file("Filt_${barcode_id}.fastq")

	shell:
	"""
	cat "${barcode_id}.fastq" | NanoFilt --quality ${params.nanofilt_quality} --maxlength ${params.nanofilt_maxlength} > Filt_${barcode_id}.fastq
	"""

}


process NanoPlotRaw {
	tag "$barcode_id"
	label "small_cpus"
	label "small_mem"

	publishDir "$params.outdir/NanoPlots/${barcode_id}/Raw", mode: "copy"

	input:
	tuple val(barcode_id), file("${barcode_id}.fastq")

	output:
	tuple val(barcode_id), path("${barcode_id}_Raw_*"), emit: nanoplot, optional: true
	tuple val(barcode_id), path("count_Raw_${barcode_id}.txt"), emit: counts

	script:
	"""
	COUNT=\$(echo \$(cat ${barcode_id}.fastq | wc -l)/4 | bc)
	TWO=2
	echo \$COUNT > count_Raw_${barcode_id}.txt
	if [ "\$COUNT" -gt "\$TWO" ]
	then
		NanoPlot -t ${task.cpus} --fastq ${barcode_id}.fastq -p ${barcode_id}_Raw_
	fi
	"""
}


process NanoPlotFilt {
	tag "$barcode_id"
	label "small_cpus"
	label "small_mem"

	publishDir "$params.outdir/NanoPlots/${barcode_id}/Filtered", mode: "copy"

	input:
	tuple val(barcode_id), file("Filt_${barcode_id}.fastq")

	output:
	tuple val(barcode_id), path("${barcode_id}_Filtered_*"), emit: nanoplot, optional: true
	tuple val(barcode_id), path("count_Filt_${barcode_id}.txt"), emit: counts

	script:
	"""
	COUNT=\$(echo \$(cat Filt_${barcode_id}.fastq | wc -l)/4 | bc)
	TWO=2
	echo \$COUNT > count_Filt_${barcode_id}.txt
	if [ "\$COUNT" -gt "\$TWO" ]
	then
		NanoPlot -t ${task.cpus} --fastq Filt_${barcode_id}.fastq -p ${barcode_id}_Filtered_
	fi
	"""
}

process SummaryTable{
	label "small_cpus"
	label "small_mem"

	publishDir "$params.outdir/NanoPlots", mode: "copy"

	input:
	file "*"
	//file "*"

	output:
	file "summary.tsv"

	shell:
	"""
	#!/usr/bin/env Rscript
	filt_files <- list.files(pattern = "_Filt_")
	raw_files <- list.files(pattern = "_Raw_")
	filt_files <- setNames(filt_files, gsub("^count_Filt_|[.]txt\$", "", filt_files))
	raw_files <- setNames(raw_files, gsub("^count_Raw_|[.]txt\$", "", raw_files))

	lp <- lapply(list(RawReads = raw_files, Filtered = filt_files), function(x) {
		vapply(x, readLines, FUN.VALUE=NA_character_)
	})

	x <- do.call(cbind, lapply(lp, function(x) { x[match(names(lp[[1]]), names(x))] }) )
	x <- as.data.frame(x)
	x\$BarCode <- rownames(x)
	x <- x[, c("BarCode", "RawReads", "Filtered")]

	write.table(x, file = "summary.tsv", sep="\t", quote=F, row.names=FALSE, col.names=TRUE)
	"""
}

process Fastq2Fasta {
	tag "$barcode_id"
	label "small_cpus"
	label "small_mem"

	input:
	tuple val(barcode_id), path("${barcode_id}.fastq")

	output:
	tuple val(barcode_id), path("${barcode_id}.fasta")

	when:
	params.stoptocheckparams == false

	shell:
	"""
	seqtk seq -A ${barcode_id}.fastq > ${barcode_id}.fasta
	"""
}

process MakeLastDB {
	label "big_cpus"

	input:
	path("silva_SSU_tax.fasta")

	output:
	file "silva.*"

	shell:
	"""
	lastdb -cR01 -P${task.cpus} silva silva_SSU_tax.fasta
	"""
}

process LastTrain {
	tag "$barcode_id"
	label "big_cpus"

	input:
	tuple val(barcode_id), path("${barcode_id}.fasta")
	file "*"
	
	
	output:
	tuple val(barcode_id), path("${barcode_id}.par")
		
	when:
	!params.stoptocheckparams

	shell:
	"""
	last-train -P${task.cpus} -Q0 silva ${barcode_id}.fasta > ${barcode_id}.par 
	"""
}

process LastAL {
	label "big_cpus"
	label "big_mem"
	tag "$barcode_id"
	publishDir "$params.outdir/LastAL", enabled: params.keepmaf, pattern: "*.maf", mode: "copy"

	input:
	tuple val(barcode_id), path("${barcode_id}.fasta"), path("${barcode_id}.par")
	path "*"

	output:
	tuple val(barcode_id), path("${barcode_id}.fasta"), path("${barcode_id}.maf")

	when:
	!params.stoptocheckparams

	shell:
	"""
	lastal -P${task.cpus} -p ${barcode_id}.par silva ${barcode_id}.fasta > ${barcode_id}.maf

	"""
}

process DAAConverter{
	label "big_cpus"
	label "big_mem"
	tag "$barcode_id"

	input:
	tuple val(barcode_id), path("${barcode_id}.fasta"), path("${barcode_id}.maf")

	output:
	tuple val(barcode_id), file("${barcode_id}.daa")

	when:
	!params.stoptocheckparams

	shell:
	"""
	java -jar /opt/DAA_Converter_v0.9.0.jar -top 20 -p ${task.cpus} -i ${barcode_id}.maf -r ${barcode_id}.fasta -o ${barcode_id}.daa
	"""
}

process DAAMeganizer{
	tag "$barcode_id"
	label "big_cpus"
	scratch true

	input:
	tuple val(barcode_id), file("${barcode_id}.daa")
	path("SSURef_Nr99_tax_silva_to_NCBI_synonyms.map")

	output:
	file("${barcode_id}.daa")

	when:
	params.stoptocheckparams == false

	shell:
	"""
	daa-meganizer -i ${barcode_id}.daa -p ${task.cpus} -s2t SSURef_Nr99_tax_silva_to_NCBI_synonyms.map --lcaAlgorithm ${params.megan_lcaAlgorithm} --lcaCoveragePercent ${params.megan_lcaCoveragePercent}
	"""
}




process ComputeComparison{
	tag "$workflow_ch"
	label "small_cpus"
	label "small_mem"
	

	publishDir "$params.outdir/Megan_Comparison", mode: "copy"

	input:
	file "*"
	val(workflow_ch)

	output:
	file("${workflow_ch}_comparison.megan")

	when:
	params.stoptocheckparams == false

	shell:
	"""
	xvfb-run --auto-servernum --server-num=1 /usr/local/bin/compute-comparison -i ./* -o ${workflow_ch}_comparison.megan
	"""
}



process ExtractOtuTable {
	tag "$workflow_ch"
	label "small_cpus"
	label "small_mem"

	publishDir "$params.outdir/Megan_Comparison", mode: "copy"

	input:
	file("${workflow_ch}_comparison.megan")
	val(workflow_ch)

	output:
	path("${workflow_ch}_OTU_Table.tsv")

	when:
	params.stoptocheckparams == false

	shell:
	"""
	#!/usr/bin/env Rscript
	rl <- readLines("${workflow_ch}_comparison.megan")
	snam <- strsplit(grep("^@Names", rl, value = TRUE), "\t")[[1]][-1]

	taxs <- grep("^TAX", rl)
	taxs <- strsplit(rl[taxs], "\t")
	taxs <- lapply(taxs, "[", -1)
	names(taxs) <- lapply(taxs, "[", 1)
	taxs <- lapply(taxs, "[", -1)
	taxs <- lapply(taxs, as.integer)

	nsam <- length(snam)
	ln <- sapply(taxs, length)
	addz <- nsam - ln

	mp <- t(mapply(function(x, add){c(x, rep(0, add))}, x=taxs, add=addz))
	colnames(mp) <- snam

	write.table(mp, file = "${workflow_ch}_OTU_Table.tsv", quote = FALSE, sep = "\t", row.names = TRUE, col.names = TRUE)
	"""
}


process MakeMinimapDB {
	label "big_cpus"

	input:
	path("silva_SSU_tax.fasta")

	output:
	path("silva_k${params.minimap2_k}.mmi")

	shell:
	"""
	minimap2 -t ${task.cpus} -k ${params.minimap2_k} -d silva_k${params.minimap2_k}.mmi silva_SSU_tax.fasta
	"""
}

process Minimap2 {
	tag "$barcode_id"
	label "big_cpus"

	input:
	tuple val(barcode_id), path("Filt_${barcode_id}.fastq")
	path("silva_k${params.minimap2_k}.mmi")

	output:
	tuple val(barcode_id), path("${barcode_id}.sam"), path("Filt_${barcode_id}.fastq")

	when:
	params.stoptocheckparams == false

	shell:
	"""
	minimap2 -t ${task.cpus} -ax ${params.minimap2_x} silva_k${params.minimap2_k}.mmi Filt_${barcode_id}.fastq > ${barcode_id}.sam
	"""
}

process Sam2Rma {
	tag "$barcode_id"
	label "big_cpus"

	input:
	tuple val(barcode_id), path("${barcode_id}.sam"), path("${barcode_id}.fastq")
	path("SSURef_Nr99_tax_silva_to_NCBI_synonyms.map")

	output:
	path("${barcode_id}.rma")

	when:
	params.stoptocheckparams == false

	shell:
	"""
	sam2rma -i ${barcode_id}.sam -r ${barcode_id}.fastq -o ${barcode_id}.rma -lg -alg longReads -lcp 80 -ram readCount -s2t SSURef_Nr99_tax_silva_to_NCBI_synonyms.map -v
	"""
}
