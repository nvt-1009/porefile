nextflow.preview.dsl = 2

params.silvaFasta = "$baseDir/silvadb/Exports/SILVA_138_SSURef_NR99_tax_silva.fasta.gz"
params.silvaAccTaxID = "$baseDir/silvadb/Exports/taxonomy/tax_slv_ssu_138.acc_taxid.gz"

params.silvaFastaURL = "https://www.arb-silva.de/fileadmin/silva_databases/current/Exports/SILVA_138_SSURef_NR99_tax_silva.fasta.gz"
params.silvaAccTaxIDURL = "https://www.arb-silva.de/fileadmin/silva_databases/current/Exports/taxonomy/tax_slv_ssu_138.acc_taxid.gz"

include {gunzip as gunzipFasta} from '../modules/processes'
include {gunzip as gunzipAccTaxid} from '../modules/processes'
include {downloadFasta} from '../modules/processes'
include {downloadAccTaxID} from '../modules/processes' 
include {trimAccTaxID} from '../modules/processes'


workflow SetSilva {
    main:

    parfasta = file( params.silvaFasta )
    paracctax = file( params.silvaAccTaxID )

    if ( ! parfasta.exists() ){

        downloadFasta()
        downloadFasta.out
            .set{ silva_fasta_ch }

    } else{
        
        if ( parfasta.getExtension() == "gz" ){

            gunzipFasta( parfasta )
            gunzipFasta.out
                .set{ silva_fasta_ch }

        } else if ( parfasta.getExtension() == "fasta" ){

            Channel.from( parfasta )
                .set{ silva_fasta_ch }

        }else{
            println("Unrecognized silva extension (not gz nor fasta).")
            System.exit(1)
        }

    }

    if ( ! paracctax.exists() ){

        downloadAccTaxID()
        downloadAccTaxID.out
            .set{ to_trim }

    } else{

        if ( paracctax.getExtension() == "gz" ){
            
            gunzipAccTaxid( paracctax )
            gunzipAccTaxid.out
                .set{ to_trim }

        } else if ( paracctax.getExtension() == "acc_taxid" ){
            
            Channel.from( paracctax )
                .set{ to_trim }

        }else{
            println("Unrecognized silva extension (not gz nor acc_taxid).")
            System.exit(1)
        }

    }

    trimAccTaxID( to_trim )
    trimAccTaxID.out
            .set{ silva_acctax_ch }
    
    emit: 
    fasta = silva_fasta_ch
    acctax = silva_acctax_ch
}