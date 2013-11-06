# Tests whether the given gene is expressed in at least in the given percentage of samples
# exprs.mat: expression matrix with genes in rows and samples in columns
# gene: gene to test
# exprs.threshold: threshold above which a gene is considered to be expressed; default: 0;
# only sensible for log-ratio expression data
# cutoff: percent samples that need to show expression for the gene to be considered expressed; 
# default: 0.5, i.e. considered expressed if expression in 50% of samples is > exprs.threshold
# returns: TRUE/FALSE
geneExpressed = function(exprs.mat, gene, exprs.threshold=0, cutoff=0.5) {
	(sum(sapply(exprs.mat[gene, , drop=FALSE], function(x) { x > exprs.threshold })) / ncol(exprs.mat)) >= cutoff
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

##' Perform paired or unpaired Wilcoxon tests.
##' Tests are only performed on common features.
##' @param mat1 data matrix with features in rows and samples in columns
##' @param mat2 data matrix with features in rows and samples in columns
##' @param paired boolean indicating if a paired test is to performed; default: TRUE
##' To run paired tests, only samples that occur in both matrices are used.
##' For unpaired tests, all samples are used.
##' @return named vector with p-values, NA if no p-value could be calculated
##' @author Andreas Schlicker
doWilcox = function(mat1, mat2, paired=TRUE) {
	# Get the two groups of samples
	if (paired) {
		common.samples = intersect(colnames(mat1), colnames(mat2))
		mat1 = mat1[, common.samples, drop=FALSE] 
		mat2 = mat2[, common.samples, drop=FALSE]
	}
	
	sapply(intersect(rownames(mat1), rownames(mat2)), 
		   function(x) { tryCatch(wilcox.test(mat1[x, ], mat2[x, ], paired=paired, exact=FALSE)$p.value, error = function(e) NA) })
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
##' @param paired boolean; if TRUE, the value of the tumor sample is compared to the value of
##' its paired normal sample; if FALSE, all tumor sample values are compared to the mean over
##' all normals
##' @return named list with two components; "summary" is a matrix with absolute (1st column) 
##' and relative (2nd column) numbers of affected samples; "samples" is a named list with all 
##' samples affected by a change in this feature
##' @author Andreas Schlicker
countAffectedSamples = function(features, tumors, normals, regulation=c("down", "up"), stddev=1, paired=TRUE) {
	if (length(features) > 0) {
		regulation = match.arg(regulation)
		
		# Get the correct comparison function
		# If we want to find genes with greater expression in tumors get the greaterThan function
		# If we want to find genes with lower expression in tumors, get the smallerThan function
		compare = switch(regulation, down=smallerThan, up=greaterThan)
		stddev = switch(regulation, down=stddev*-1, up=stddev)
		
		if (!is.matrix(normals)) {
			normals = matrixFromVector(normals)
			rownames(normals) = features
		}
		
		if (!is.matrix(tumors)) {
			tumors = matrixFromVector(tumors)
			rownames(tumors) = features
		}
		
		common = intersect(rownames(tumors), intersect(features, rownames(normals)))
		missing = setdiff(features, common)
		
		matched.samples = intersect(colnames(tumors), colnames(normals))
		if (length(matched.samples) == 0) {
			paired = FALSE
			warning("No paired samples found. Performing unpaired analysis!")
		}
		if (paired) {
			# Which tumor samples have a matched normal?
			normFactor = length(matched.samples)
			
			# All differences 
			deltaMat = tumors[common, matched.samples, drop=FALSE] - normals[common, matched.samples, drop=FALSE]
			# Per gene standard deviation of the differences
			deltaSd = apply(deltaMat, 1, function(x) { sd(x, na.rm=TRUE) })
			
			# Get the names of the samples that are affected
			samples = apply(deltaMat - stddev*deltaSd, 1, function(x) { names(which(compare(x, 0))) })
			# A sample is upregulated (downregulated) if the difference value is greater (smaller) than stddev-many standard deviations
			affected = unlist(lapply(samples, function(x) { length(x) }))
		} else {
			# Number of samples to normalize with
			normFactor = ncol(tumors)
			# Calculate comparison value across normals
			normal.cmp = apply(normals[common, , drop=FALSE], 1, mean, na.rm=TRUE)
					   + stddev*apply(normals[common, , drop=FALSE], 1, sd, na.rm=TRUE)
			
			# Which samples are affected by feature
			# No need to cut off the feature name here
			samples = lapply(common, function(x) { names(which(compare(tumors[x, ], normal.cmp[x]))) })
			names(samples) = common
			# Count affected samples
			affected = unlist(lapply(samples, function(x) { length(x) }))
		}
		
		# Add all missing features and resort
		affected[missing] = NA
		affected = affected[features]
		samples[missing] = NA
		samples = samples[features]
		
		res = list(summary=cbind(absolute=affected, relative=(affected / normFactor)),
				   samples=samples)
	} else {
		res = list()
	}
	
	res
}

##' Compute the union of all elements of the input list.
##' @samples a named list with vectors to get the union of
##' @use a vector scores; if given, an entry of 1 indicates
##' that this sample list has to be taken into account; default: NULL
##' Both arguments need to use the same names for elements
##' @return the union
##' @author Andreas Schlicker
sampleUnion = function(samples, use=NULL) {
	res = c()
	indexes = names(samples)
	if (is.null(indexes)) {
		indexes = 1:length(samples)
	}
	if (!is.null(use)) {
		indexes = names(which(use == 1))
	}
	for (i in indexes) {
		res = union(res, samples[[i]])
	}
	
	res
}

##' Imputes missing data using the impute.knn function as implemented 
##' in the "impute" library. If this library is not installed or impute=FALSE, all
##' probes with missing values will be removed.
##' @param data.data matrix with features in rows and samples in columns
##' @param impute boolean indicating whether missing values should be imputed
##' @param no.na threshold giving the number of missing values from which on a
##' feature will be removed. By default, a feature is only removed if its value is
##' missing for all samples.
##' @return cleaned matrix
##' @author Andreas Schlickers
cleanMatrix = function(data.mat, impute=TRUE, no.na=ncol(data.mat)) {
	# How many values are missing for each probe?
	no.nas = apply(data.mat, 1, function(x) { sum(is.na(x)) })
	if (!require(impute) || !impute) {
		print("Could not load library \"impute\". All probes with missing values will be removed")
		# Remove probes with missing values
		exclude = which(no.nas > 0)
		meth.data.imputed = list(data=data.mat[-exclude, ])
	} else {
		# Probes to be excluded
		exclude = which(no.nas > no.na)
		# Impute missing values
		meth.data.imputed = impute.knn(data.mat[-exclude, ])
	}
	
	meth.data.imputed
}

##' Calculates the difference in mean between tumors and normals.
##' Filters out all features not contained in both matrices.
##' @param tumors matrix with tumor data
##' @param normals matrix with normal data
##' @return vector with differences
##' @author Andreas Schlicker
meanDiff = function(tumors, normals) {
	common.features = intersect(rownames(tumors), rownames(normals))
	apply(tumors[common.features, , drop=FALSE], 1, mean, na.rm=TRUE) - apply(normals[common.features, , drop=FALSE], 1, mean, na.rm=TRUE)
}
