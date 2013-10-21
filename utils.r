# Tests whether the given gene is expressed in at least in the given percentage of samples
# exprs.mat: expression matrix with genes in rows and samples in columns
# gene: gene to test
# exprs.threshold: threshold above which a gene is considered to be expressed; default: 0;
# only sensible for log-ratio expression data
# cutoff: percent samples that need to show expression for the gene to be considered expressed; 
# default: 0.5, i.e. considered expressed if expression in 50% of samples is > exprs.threshold
# returns: TRUE/FALSE
geneExpressed = function(exprs.mat, gene, exprs.threshold=0, cutoff=0.5) {
	(sum(sapply(exprs.mat[gene, ], function(x) { x > exprs.threshold })) / ncol(exprs.mat)) >= cutoff
}

# Convenience function to test a number of genes whether they are expressed or not
# exprs.mat: expression matrix with genes in rows and samples in columns
# gene: gene to test
# exprs.threshold: threshold above which a gene is considered to be expressed; default: 0;
# only sensible for log-ratio expression data
# cutoff: percent samples that need to show expression for the gene to be considered expressed; 
# default: 0.5, i.e. considered expressed if expression in 50% of samples is > exprs.threshold
# returns: a boolean vector
genesExpressed = function(exprs.mat, genes, exprs.threshold=0, cutoff=0.5) { 
	sapply(genes, function(gene) { geneExpressed(exprs.mat, gene, exprs.threshold, cutoff) })
}

# Perform Wilcoxon tests on the given matrix.
# If the matchedSamples argument is defined, a paired test is performed. In this
# case, the first length(matchedSamples) number of columns need to contain group
# 1 and the remaining columns samples in group 2. Samples in groups 1
# and 2 need to be in matched order.
# If a non-paired test is to be performed, groups should be a named vector of
# 1 and 2 indicating which samples belong to group 1 and 2, respectively.
doWilcox = function(inpMat, matchedSamples=NULL, groups=NULL) {
  # Paired Wilcoxon test?
  paired = !is.null(matchedSamples)
 
  # Get the two groups of samples
  if (paired) {
    group1 = 1:length(matchedSamples) 
    group2 = (length(matchedSamples)+1):ncol(inpMat)
  } else {
    group1 = which(colnames(inpMat) %in% names(groups[groups == 1]))
    group2 = which(colnames(inpMat) %in% names(groups[groups == 2]))
  }
  
  wilcox.p = apply(inpMat, 1, function(x) { tryCatch(wilcox.test(x[group1], x[group2], paired=paired, exact=FALSE)$p.value, error = function(e) NA) })
  
  return(wilcox.p)
}

# Perform Bartlett's test on each row of the given matrix.
# Groups should be a named vector indicating which samples belong to the  
# different groups.
doBartlett = function(inpMat, groups=NULL) {
  bartlett.p = apply(inpMat, 1, function(x) { tryCatch(bartlett.test(x, g=groups)$p.value, error = function(e) NA) })
  
  return(bartlett.p)
}

# Perform Levene's test on each row of the given matrix.
# groups is a factor indicating which samples belong to the different groups.
# location one of "median", "mean", "trim.mean"
doLevene = function(inpMat, groups, location=c("median", "mean", "trim.mean")) {
	# Load the package for performing Levene's test
	require(lawstat)
	# Get the right 
	location = match.arg(location)
	
	levene.p = apply(inpMat, 1, function(x) { tryCatch(levene.test(x, g=groups)$p.value, error = function(e) NA) })
  
	return(levene.p)
}

# Calculate prioritization score by summing over the rows
# x should be a matrix with data types in the columns
dataTypeScore = function(mat) {
  apply(mat, 1, sum, na.rm=TRUE) 
}

greaterThan = function(x, y) { x > y }
smallerThan = function(x, y) { x < y }

##' Creates a helper function to count the elements greater
##' than the given cutoff.
##' @param cutoff cutoff value to apply
##' @return the number of elements greater than the cutoff
##' @export
##' @author Andreas Schlicker
gtCutoff = function(cutoff) { function(x) { sum(x > cutoff) } }

##' Creates a helper function to find the percentage of elements
##' that are greater than the given cutoff.
##' @param cutoff cutoff value to apply
##' @return the percentage of elements greater than the cutoff (ranging from
##' 0 to 1.
##' @export
##' @author Andreas Schlicker
gtCutoffPercent = function(cutoff) { function(x) { sum(x > cutoff) / length(x) } }

##' Creates a helper function to count the elements less
##' than the given cutoff.
##' @param cutoff cutoff value to apply
##' @return the number of elements less than the cutoff
##' @export
##' @author Andreas Schlicker
ltCutoff = function(cutoff) { function(x) { sum(x < cutoff) } }

##' Creates a helper function to find the percentage of elements
##' that are less than the given cutoff.
##' @param cutoff cutoff value to apply
##' @return the percentage of elements less than the cutoff (ranging from
##' 0 to 1.
##' @export
##' @author Andreas Schlicker
ltCutoffPercent = function(cutoff) { function(x) { sum(x < cutoff) / length(x) } }

##' Convert a vector into a matrix with one row.
##' Names of the vector are preserved as colnames.
##' @param vec input vector
##' @return the new matrix
##' @author Andreas Schlicker
matrixFromVector = function(vec) {
	tmp = matrix(vec, nrow=1)
	colnames(tmp) = names(vec)
	tmp
}

##' Count the number of tumors that differ from the mean in normal samples.
##' All features that are not present in the tumors and/or normals matrix are filtered out.
##' @param feature vector with feature IDs
##' @param tumors numeric matrix with features in rows and tumors samples in columns
##' @param normals numeric matrix with features in rows and normal samples in columns
##' @param regulation either "down" or "up" to test for values lower than or greater than the
##' normal mean
##' @param stddev how many standard deviations does a sample have to be away from the mean
##' @return named list with two components; "summary" is a matrix with absolute (1st column) 
##' and relative (2nd column) numbers of affected samples; "samples" is a named list with all 
##' samples affected by a change in this feature
##' @author Andreas Schlicker
countAffectedSamples = function(features, tumors, normals, regulation=c("down", "up"), stddev=1) {
	regulation = match.arg(regulation)
	
	# Get the correct comparison function
	# If we want to find genes with greater expression in tumors get the greaterThan function
	# If we want to find genes with lower expression in tumors, get the smallerThan function
	compare = switch(regulation, down=smallerThan, up=greaterThan)
	stddev = switch(regulation, down=stddev*-1, up=stddev)
	
	normal.means = apply(normals, 1, mean, na.rm=TRUE)
	normal.sd = apply(normals, 1, sd, na.rm=TRUE)
	
	common = intersect(features, intersect(rownames(tumors), rownames(normals)))
	
	affected = sapply(common, function(x) { sum(compare(tumors[x, ], normal.means[x]+stddev*normal.sd[x])) })
	samples=lapply(common, function(x) { names(which(compare(tumors[x, ], normal.means[x]+stddev*normal.sd[x]))) })
	names(samples) = common
	
	list(summary=cbind(absolute=affected, relative=(affected / ncol(tumors))),
		 samples=samples)
}

