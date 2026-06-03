require(fUnitRoots)
require(lmtest)


# order<-1
# max.order<-5
# variable<-SP500$SP500
# max.augmentations<-1
# augmentations<-0
testdf2 <- function(variable, test.type, max.augmentations, max.order)
	{
	results_adf <- NULL
	variable <- coredata(variable[!is.na(variable)])
	
	for(augmentations in 0:max.augmentations)
		{
		df.test_ <- adfTest(variable, lags = augmentations, type = test.type)
		df_ <- as.numeric(df.test_@test$statistic)
		p_adf <- as.numeric(df.test_@test$p.value)
		resids_ <- df.test_@test$lm$residuals
		
	
		bgtest_<-list()
		bgodfrey<-list()
		p_bg<-list()
	
		
		for (order in 1:(max.order+1))
		{
  		bgtest_[[order]] <- bgtest(resids_~1, order = order-1)
  		bgodfrey[[order]]<- bgtest_[[order]]["statistic"]
  		# names(bgodfrey[[order]]) <- NULL
  		p_bg[[order]]<- bgtest_[[order]]["p.value"]
  		}
		results_adf <- rbind(results_adf, data.frame(augmentations = augmentations, adf = df_, p_adf = p_adf,
                                                 bgodfrey = bgodfrey, p_bg = p_bg))
		rm(df.test_, df_, resids_, bgtest_, bgodfrey, p_bg)
		}
	
	results_adf <- results_adf[results_adf$augmentations >= 0,]
	
	row.names(results_adf) <- NULL
	
	plot(variable, type = "l", col = "blue", lwd = 2, main = "Plot of the examined variable")

	results_adf$p_bg.p.value<-NULL
	
	return(results_adf)
	}	