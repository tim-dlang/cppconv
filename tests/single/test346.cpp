// from libxml2 xmllint.c

int strcmp(const char *s1, const char *s2);

void f(const char *arg)
{
    int debug = 0, shell = 0, copy = 0, recovery = 0, noout = 0, htmlout = 0;
    int nowrap = 0, html = 0, loaddtd = 0, dtdattrs = 0, dropdtd = 0, repeat = 0;
    int testIO = 0, xmlGetWarningsDefaultValue = 0, noblanks = 0, sax = 0;
    int chkregister = 0, load_trace = 0;
    const char *output = 0, *encoding = 0;

	if ((!strcmp(arg, "-debug")) || (!strcmp(arg, "--debug")))
	    debug++;
	else
#ifdef LIBXML_DEBUG_ENABLED
	if ((!strcmp(arg, "-shell")) ||
	         (!strcmp(arg, "--shell"))) {
	    shell++;
            noout = 1;
        } else
#endif
#ifdef LIBXML_TREE_ENABLED
	if ((!strcmp(arg, "-copy")) || (!strcmp(arg, "--copy")))
	    copy++;
	else
#endif /* LIBXML_TREE_ENABLED */
	if ((!strcmp(arg, "-recover")) ||
	         (!strcmp(arg, "--recover"))) {
	    recovery++;
	} else if ((!strcmp(arg, "-noout")) ||
	         (!strcmp(arg, "--noout")))
	    noout++;
#ifdef LIBXML_OUTPUT_ENABLED
	else if ((!strcmp(arg, "-o")) ||
	         (!strcmp(arg, "-output")) ||
	         (!strcmp(arg, "--output"))) {
	    output = arg;
	}
#endif /* LIBXML_OUTPUT_ENABLED */
	else if ((!strcmp(arg, "-htmlout")) ||
	         (!strcmp(arg, "--htmlout")))
	    htmlout++;
	else if ((!strcmp(arg, "-nowrap")) ||
	         (!strcmp(arg, "--nowrap")))
	    nowrap++;
#ifdef LIBXML_HTML_ENABLED
	else if ((!strcmp(arg, "-html")) ||
	         (!strcmp(arg, "--html"))) {
	    html++;
        }
    else if ((!strcmp(arg, "-nodefdtd")) ||
	         (!strcmp(arg, "--nodefdtd"))) {
            nodefdtd++;
        }
#endif /* LIBXML_HTML_ENABLED */
	else if ((!strcmp(arg, "-loaddtd")) ||
	         (!strcmp(arg, "--loaddtd"))) {
	    loaddtd++;
	} else if ((!strcmp(arg, "-dtdattr")) ||
	         (!strcmp(arg, "--dtdattr"))) {
	    loaddtd++;
	    dtdattrs++;
	}
#ifdef LIBXML_VALID_ENABLED
	else if ((!strcmp(arg, "-valid")) ||
	         (!strcmp(arg, "--valid"))) {
	    valid++;
	} else if ((!strcmp(arg, "-dtdvalidfpi")) ||
	         (!strcmp(arg, "--dtdvalidfpi"))) {
	    dtdvalidfpi = arg;
	    loaddtd++;
        }
#endif /* LIBXML_VALID_ENABLED */
	else if ((!strcmp(arg, "-dropdtd")) ||
	         (!strcmp(arg, "--dropdtd")))
	    dropdtd++;
	else if ((!strcmp(arg, "-repeat")) ||
	         (!strcmp(arg, "--repeat"))) {
	    if (repeat)
	        repeat *= 10;
	    else
	        repeat = 100;
	}
#ifdef LIBXML_PUSH_ENABLED
	else if ((!strcmp(arg, "-push")) ||
	         (!strcmp(arg, "--push")))
	    push++;
	else if ((!strcmp(arg, "-pushsmall")) ||
	         (!strcmp(arg, "--pushsmall"))) {
	    push++;
            pushsize = 10;
        }
#endif /* LIBXML_PUSH_ENABLED */
#ifdef HAVE_MMAP
	else if ((!strcmp(arg, "-memory")) ||
	         (!strcmp(arg, "--memory")))
	    memory++;
#endif
	else if ((!strcmp(arg, "-testIO")) ||
	         (!strcmp(arg, "--testIO")))
	    testIO++;
#ifdef LIBXML_XINCLUDE_ENABLED
	else if ((!strcmp(arg, "-xinclude")) ||
	         (!strcmp(arg, "--xinclude"))) {
	    xinclude++;
	}
	else if ((!strcmp(arg, "-noxincludenode")) ||
	         (!strcmp(arg, "--noxincludenode"))) {
	    xinclude++;
	}
	else if ((!strcmp(arg, "-nofixup-base-uris")) ||
	         (!strcmp(arg, "--nofixup-base-uris"))) {
	    xinclude++;
	}
#endif
#ifdef LIBXML_OUTPUT_ENABLED
#ifdef LIBXML_ZLIB_ENABLED
	else if ((!strcmp(arg, "-compress")) ||
	         (!strcmp(arg, "--compress"))) {
	    compress++;
        }
#endif
#endif /* LIBXML_OUTPUT_ENABLED */
	else if ((!strcmp(arg, "-nowarning")) ||
	         (!strcmp(arg, "--nowarning"))) {
	    xmlGetWarningsDefaultValue = 0;
        }
	else if ((!strcmp(arg, "-pedantic")) ||
	         (!strcmp(arg, "--pedantic"))) {
	    xmlGetWarningsDefaultValue = 1;
        }
#ifdef LIBXML_DEBUG_ENABLED
	else if ((!strcmp(arg, "-debugent")) ||
		 (!strcmp(arg, "--debugent"))) {
	    debugent++;
	    xmlParserDebugEntities = 1;
	}
#endif
#ifdef LIBXML_C14N_ENABLED
	else if ((!strcmp(arg, "-c14n")) ||
		 (!strcmp(arg, "--c14n"))) {
	    canonical++;
	}
	else if ((!strcmp(arg, "-c14n11")) ||
		 (!strcmp(arg, "--c14n11"))) {
	    canonical_11++;
	}
	else if ((!strcmp(arg, "-exc-c14n")) ||
		 (!strcmp(arg, "--exc-c14n"))) {
	    exc_canonical++;
	}
#endif
#ifdef LIBXML_CATALOG_ENABLED
	else if ((!strcmp(arg, "-catalogs")) ||
		 (!strcmp(arg, "--catalogs"))) {
	    catalogs++;
	} else if ((!strcmp(arg, "-nocatalogs")) ||
		 (!strcmp(arg, "--nocatalogs"))) {
	    nocatalogs++;
	}
#endif
	else if ((!strcmp(arg, "-encode")) ||
	         (!strcmp(arg, "--encode"))) {
	    encoding = arg;
        }
	else if ((!strcmp(arg, "-noblanks")) ||
	         (!strcmp(arg, "--noblanks"))) {
	    noblanks++;
        }
	else if ((!strcmp(arg, "-maxmem")) ||
	         (!strcmp(arg, "--maxmem"))) {
        }
	else if ((!strcmp(arg, "-format")) ||
	         (!strcmp(arg, "--format"))) {
	     noblanks++;
#ifdef LIBXML_OUTPUT_ENABLED
	     format = 1;
#endif /* LIBXML_OUTPUT_ENABLED */
	}
	else if ((!strcmp(arg, "-pretty")) ||
	         (!strcmp(arg, "--pretty"))) {
#ifdef LIBXML_OUTPUT_ENABLED
       if (arg != NULL) {
       }
#endif /* LIBXML_OUTPUT_ENABLED */
	}
#ifdef LIBXML_READER_ENABLED
	else if ((!strcmp(arg, "-stream")) ||
	         (!strcmp(arg, "--stream"))) {
	     stream++;
	}
	else if ((!strcmp(arg, "-walker")) ||
	         (!strcmp(arg, "--walker"))) {
	     walker++;
             noout++;
#ifdef LIBXML_PATTERN_ENABLED
        } else if ((!strcmp(arg, "-pattern")) ||
                   (!strcmp(arg, "--pattern"))) {
	    pattern = arg;
#endif
	}
#endif /* LIBXML_READER_ENABLED */
#ifdef LIBXML_SAX1_ENABLED
	else if ((!strcmp(arg, "-sax1")) ||
	         (!strcmp(arg, "--sax1"))) {
	    sax1++;
	}
#endif /* LIBXML_SAX1_ENABLED */
	else if ((!strcmp(arg, "-sax")) ||
	         (!strcmp(arg, "--sax"))) {
	    sax++;
	}
	else if ((!strcmp(arg, "-chkregister")) ||
	         (!strcmp(arg, "--chkregister"))) {
	    chkregister++;
#ifdef LIBXML_SCHEMAS_ENABLED
	} else if ((!strcmp(arg, "-relaxng")) ||
	         (!strcmp(arg, "--relaxng"))) {
	    relaxng = arg;
	    noent++;
	} else if ((!strcmp(arg, "-schema")) ||
	         (!strcmp(arg, "--schema"))) {
	    schema = arg;
	    noent++;
#endif
#ifdef LIBXML_SCHEMATRON_ENABLED
	} else if ((!strcmp(arg, "-schematron")) ||
	         (!strcmp(arg, "--schematron"))) {
	    schematron = arg;
	    noent++;
#endif
        } else if ((!strcmp(arg, "-nonet")) ||
                   (!strcmp(arg, "--nonet"))) {
        } else if ((!strcmp(arg, "-nocompact")) ||
                   (!strcmp(arg, "--nocompact"))) {
	} else if ((!strcmp(arg, "-load-trace")) ||
	           (!strcmp(arg, "--load-trace"))) {
	    load_trace++;
        } else if ((!strcmp(arg, "-path")) ||
                   (!strcmp(arg, "--path"))) {
#ifdef LIBXML_XPATH_ENABLED
        } else if ((!strcmp(arg, "-xpath")) ||
                   (!strcmp(arg, "--xpath"))) {
	    noout++;
	    xpathquery = arg;
#endif
	} else {
	    return;
	}
}
