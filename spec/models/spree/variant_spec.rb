require 'spec_helper'

describe Spree::Variant do

  it 'has a valid factory' do
    expect(build(:travel_variant)).to be_valid
  end

end