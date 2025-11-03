import type { Configuration, ExternalItemFunctionData } from 'webpack';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import CopyWebpackPlugin from 'copy-webpack-plugin';
// @ts-ignore
import ReplaceInFileWebpackPlugin from 'replace-in-file-webpack-plugin';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const config = async (env: any): Promise<Configuration> => {
  const isProd = env.production === true;

  return {
    mode: isProd ? 'production' : 'development',
    target: 'web',

    entry: {
      module: './src/module.ts',
    },

    output: {
      path: path.resolve(__dirname, 'dist'),
      filename: '[name].js',
      libraryTarget: 'amd',
      clean: true,
    },

    externals: [
      'lodash',
      'react',
      'react-dom',
      '@grafana/data',
      '@grafana/ui',
      '@grafana/runtime',
      (data: ExternalItemFunctionData, callback: any) => {
        const prefix = 'grafana/';
        if (data.request && data.request.indexOf(prefix) === 0) {
          return callback(undefined, data.request.substr(prefix.length));
        }
        callback();
      },
    ],

    resolve: {
      extensions: ['.ts', '.tsx', '.js', '.jsx'],
      modules: [path.resolve(__dirname, 'src'), 'node_modules'],
    },

    module: {
      rules: [
        {
          test: /\.(ts|tsx)$/,
          exclude: /node_modules/,
          use: {
            loader: 'swc-loader',
            options: {
              jsc: {
                parser: {
                  syntax: 'typescript',
                  tsx: true,
                  decorators: false,
                  dynamicImport: true,
                },
                target: 'es2015',
                loose: false,
                externalHelpers: false,
              },
            },
          },
        },
        {
          test: /\.css$/,
          use: ['style-loader', 'css-loader'],
        },
        {
          test: /\.s[ac]ss$/,
          use: ['style-loader', 'css-loader', 'sass-loader'],
        },
        {
          test: /\.(png|jpg|gif|svg)$/,
          type: 'asset/resource',
        },
      ],
    },

    plugins: [
      new CopyWebpackPlugin({
        patterns: [
          { from: 'src/plugin.json', to: '.' },
          { from: 'src/img/*', to: 'img/[name][ext]', noErrorOnMissing: true },
          { from: 'README.md', to: '.' },
          { from: 'CHANGELOG.md', to: '.', noErrorOnMissing: true },
          { from: 'LICENSE', to: '.', noErrorOnMissing: true },
        ],
      }),
      new ReplaceInFileWebpackPlugin([
        {
          dir: 'dist',
          files: ['plugin.json', 'README.md'],
          rules: [
            {
              search: /%VERSION%/g,
              replace: '1.0.0',
            },
            {
              search: /%TODAY%/g,
              replace: new Date().toISOString().substring(0, 10),
            },
          ],
        },
      ]),
    ],

    devtool: isProd ? 'source-map' : 'eval-source-map',

    optimization: {
      minimize: isProd,
    },
  };
};

export default config;
