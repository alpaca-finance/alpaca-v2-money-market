import { Command } from "commander";
import { ConfigFileHelper } from "../../deploy/file-helper.ts/config-file.helper";
import { AssetTier, Market, reverseAssetTier } from "../../deploy/interfaces";

async function main(
  name: string,
  tier: string,
  token: string,
  ibToken: string,
  debtToken: string,
  interestModel: string
) {
  const configFileHelper = new ConfigFileHelper();

  const newMarket: Market = {
    name,
    tier: reverseAssetTier[Number(tier) as AssetTier],
    token,
    ibToken,
    debtToken,
    interestModel,
  };

  configFileHelper.addNewMarket(newMarket);
  console.log("✅ Done");
}

const program = new Command();
program.requiredOption("-n, --name <name>");
program.requiredOption("-tier, --tier <tier>");
program.requiredOption("-t, --token <token>");
program.requiredOption("-i, --ibToken <ibToken>");
program.requiredOption("-d, --debtToken <debtToken>");
program.requiredOption("-int, --interestModel <interestModel>");

program.parse(process.argv);

const options = program.opts();

main(options.name, options.tier, options.token, options.ibToken, options.debtToken, options.interestModel)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
